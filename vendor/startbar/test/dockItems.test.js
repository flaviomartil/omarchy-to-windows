const test = require("node:test");
const assert = require("node:assert/strict");
const DockModel = require("../DockModel.js");
const { applyIntent, effectiveView } = require("../DockConfig.js");

// A toplevel shaped like Quickshell's HyprlandToplevel.
function toplevel(address, overrides) {
  return Object.assign(
    {
      address: address,
      title: "title " + address,
      activated: false,
      urgent: false,
      workspace: { name: "1" },
      lastIpcObject: { class: "App", floating: false, fullscreen: 0, pinned: false },
    },
    overrides,
  );
}

const APPS = { firefox: { id: "firefox" }, alacritty: { id: "alacritty" }, "chrome-x.com__-Default": { id: "x-webapp" } };
const lookup = (name) => APPS[name] || null;
const byId = (id) => APPS[id] || null;

function input(toplevels, overrides) {
  return Object.assign(
    { toplevels: toplevels, now: 1000, pins: [], pinPlacements: [], grouped: false, lookup: lookup, byId: byId },
    overrides,
  );
}

function withClass(address, cls, overrides) {
  return toplevel(address, Object.assign({ lastIpcObject: { class: cls } }, overrides));
}

function keys(result) {
  return result.items.map((item) => item.key);
}

test("Windows become Window Items in the order they first appeared", () => {
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([withClass("0xb", "alacritty")]));
  result = DockModel.refreshItems(result.state, input([withClass("0xb", "alacritty"), withClass("0xa", "firefox")]));
  assert.deepEqual(keys(result), ["window:0xb", "window:0xa"]);
});

test("a Window keeps its Launch Order rank when an earlier Window closes", () => {
  let result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([withClass("0xa", "firefox"), withClass("0xb", "alacritty"), withClass("0xc", "firefox", { workspace: { name: "2" } })]),
  );
  result = DockModel.refreshItems(result.state, input([withClass("0xb", "alacritty"), withClass("0xc", "firefox")]));
  assert.deepEqual(result.state.openedAt, { "0xb": 1, "0xc": 2 });
  assert.equal(result.state.nextOpenedAt, 3);
});

test("a closed Window's rank is not reused if its address comes back", () => {
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([withClass("0xa", "firefox")]));
  result = DockModel.refreshItems(result.state, input([]));
  result = DockModel.refreshItems(result.state, input([withClass("0xa", "firefox")]));
  assert.equal(result.state.openedAt["0xa"], 1);
});

test("toplevels with no address are skipped", () => {
  const result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([toplevel("", {}), toplevel(undefined, {}), withClass("0xa", "firefox")]),
  );
  assert.deepEqual(keys(result), ["window:0xa"]);
  assert.deepEqual(Object.keys(result.handles), ["0xa"]);
});

test("a Window with no class yet is held back, then shown once classWaitMs has passed", () => {
  const classless = toplevel("0xa", { lastIpcObject: {} });
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([classless], { now: 1000 }));
  assert.deepEqual(keys(result), []);
  assert.equal(result.held, true);

  result = DockModel.refreshItems(result.state, input([classless], { now: 1000 + DockModel.CLASS_WAIT_MS - 1 }));
  assert.equal(result.held, true);
  assert.deepEqual(keys(result), []);

  result = DockModel.refreshItems(result.state, input([classless], { now: 1000 + DockModel.CLASS_WAIT_MS }));
  assert.equal(result.held, false);
  assert.deepEqual(keys(result), ["window:0xa"]);
});

test("a held Window still takes its place in Launch Order and keeps its handle", () => {
  const classless = toplevel("0xa", { lastIpcObject: {} });
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([classless, withClass("0xb", "firefox")]));
  assert.deepEqual(keys(result), ["window:0xb"]);
  assert.equal(result.handles["0xa"], classless);
  assert.equal(result.state.openedAt["0xa"], 0);
});

test("a Window whose class arrives while held is shown at once, in its App's group", () => {
  const classless = toplevel("0xa", { lastIpcObject: {} });
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([classless], { grouped: true }));
  const classed = withClass("0xa", "firefox");
  result = DockModel.refreshItems(result.state, input([classed], { now: 1100, grouped: true }));
  assert.equal(result.held, false);
  assert.equal(result.items[0].app.id, "firefox");
  assert.deepEqual(result.state.firstSeen, { "0xa": 1000 });
});

test("a held Window that closes drops its first-seen time", () => {
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([toplevel("0xa", { lastIpcObject: {} })]));
  assert.deepEqual(Object.keys(result.state.firstSeen), ["0xa"]);
  result = DockModel.refreshItems(result.state, input([]));
  assert.deepEqual(result.state.firstSeen, {});
});

test("a title change alone is not a change; titles still follow it", () => {
  let result = DockModel.refreshItems(DockModel.newItemsState(), input([withClass("0xa", "firefox", { title: "one" })]));
  assert.equal(result.changed, true);
  result = DockModel.refreshItems(result.state, input([withClass("0xa", "firefox", { title: "two" })]));
  assert.equal(result.changed, false);
  assert.equal(result.titles["0xa"], "two");
});

test("focus, a new Window and a new workspace are changes", () => {
  const base = [withClass("0xa", "firefox")];
  let result = DockModel.refreshItems(DockModel.newItemsState(), input(base));
  const first = result.state;
  assert.equal(DockModel.refreshItems(first, input([withClass("0xa", "firefox", { activated: true })])).changed, true);
  assert.equal(DockModel.refreshItems(first, input([withClass("0xa", "firefox", { workspace: { name: "3" } })])).changed, true);
  assert.equal(DockModel.refreshItems(first, input(base.concat(withClass("0xb", "alacritty")))).changed, true);
  assert.equal(DockModel.refreshItems(first, input(base)).changed, false);
});

test("an App appearing in DesktopEntries later is a change", () => {
  const toplevels = [withClass("0xa", "late")];
  let result = DockModel.refreshItems(DockModel.newItemsState(), input(toplevels));
  assert.equal(result.items[0].app, null);
  result = DockModel.refreshItems(result.state, input(toplevels, { lookup: (name) => (name === "late" ? { id: "late" } : null) }));
  assert.equal(result.changed, true);
  assert.equal(result.items[0].app.id, "late");
});

test("an Edge web app's Window resolves to the App the chrome- class names", () => {
  const result = DockModel.refreshItems(DockModel.newItemsState(), input([withClass("0xa", "msedge-x.com__-Default")]));
  assert.equal(result.items[0].app.id, "x-webapp");
});

test("resolveApp: the class itself first, then the Chromium alias, else null", () => {
  assert.equal(DockModel.resolveApp("firefox", lookup).id, "firefox");
  assert.equal(DockModel.resolveApp("brave-x.com__-Default", lookup).id, "x-webapp");
  assert.equal(DockModel.resolveApp("nothing", lookup), null);
  assert.equal(DockModel.resolveApp("", lookup), null);
  assert.equal(DockModel.resolveApp(undefined, lookup), null);
});

test("a long class or title is clipped on the way in", () => {
  const long = "x".repeat(DockModel.MAX_WINDOW_TEXT + 50);
  const result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([toplevel("0xa", { title: long, lastIpcObject: { class: long } })]),
  );
  assert.equal(result.items[0].window.class.length, DockModel.MAX_WINDOW_TEXT);
  assert.equal(result.titles["0xa"].length, DockModel.MAX_WINDOW_TEXT);
});

test("the workspace falls back to the IPC object when the toplevel has none", () => {
  const result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([toplevel("0xa", { workspace: null, lastIpcObject: { class: "firefox", workspace: { name: "7" } } })]),
  );
  assert.equal(result.items[0].window.workspace, "7");
});

test("Pins hold their slot; a Pin's persisted Placed position is applied", () => {
  const result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([withClass("0xb", "alacritty")], {
      pins: ["firefox", "alacritty"],
      pinPlacements: [{ key: "pin:firefox", index: 1 }],
    }),
  );
  assert.deepEqual(keys(result), ["window:0xb", "pin:firefox"]);
});

test("awaitingToplevels: a held Window, or a Window Item with no App and no letter", () => {
  assert.equal(DockModel.awaitingToplevels([], true), true);
  assert.equal(DockModel.awaitingToplevels([], false), false);
  assert.equal(DockModel.awaitingToplevels([{ kind: "window", app: null, letter: "" }], false), true);
  assert.equal(DockModel.awaitingToplevels([{ kind: "window", app: null, letter: "z" }], false), false);
  assert.equal(DockModel.awaitingToplevels([{ kind: "pin", app: null, letter: "" }], false), false);
});

test("openedWindow reads the address and class from an openwindow event, commas in the title or not", () => {
  assert.deepEqual(DockModel.openedWindow("0xabc,2,firefox,Some page"), { address: "0xabc", class: "firefox" });
  assert.deepEqual(DockModel.openedWindow("0xabc,2,firefox,Hello, world, again"), { address: "0xabc", class: "firefox" });
  assert.deepEqual(DockModel.openedWindow("0xabc,2"), { address: "0xabc", class: "" });
});

// keyOps -------------------------------------------------------------------

function applyOps(list, ops) {
  const out = list.slice();
  for (const op of ops) {
    if (op.op === "remove") out.splice(op.at, 1);
    else if (op.op === "move") out.splice(op.to, 0, out.splice(op.from, 1)[0]);
    else out.splice(op.at, 0, op.key);
  }
  return out;
}

test("keyOps turns any list into any other, keeping Items that stay", () => {
  const cases = [
    [[], ["a", "b"]],
    [["a", "b"], []],
    [["a", "b", "c"], ["c", "a", "b"]],
    [["a", "b", "c"], ["b", "c", "a"]],
    [["a", "b", "c"], ["a", "x", "c"]],
    [["a", "b", "c", "d"], ["d", "c", "b", "a"]],
    [["a", "b", "c"], ["a", "b", "c"]],
  ];
  for (const [from, to] of cases) assert.deepEqual(applyOps(from, DockModel.keyOps(from, to)), to, from + " -> " + to);
});

test("keyOps does nothing when nothing changed, and never removes an Item that stays", () => {
  assert.deepEqual(DockModel.keyOps(["a", "b"], ["a", "b"]), []);
  const ops = DockModel.keyOps(["a", "b", "c"], ["c", "a", "b"]);
  assert.deepEqual(ops, [{ op: "move", from: 2, to: 0 }]);
});

// Placed ------------------------------------------------------------------

test("dropPlaced: a Pin's position is for settings, a Window's and Group's stay in memory", () => {
  let result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([withClass("0xa", "alacritty"), withClass("0xb", "alacritty")], { pins: ["firefox"] }),
  );
  assert.deepEqual(keys(result), ["pin:firefox", "window:0xa", "window:0xb"]);

  const dropped = DockModel.dropPlaced(result.state, result.items, [], "window:0xb", 0);
  assert.deepEqual(dropped.pins, []);
  assert.deepEqual(dropped.state.windowPlacements, { "window:0xb": 0 });

  const pinDropped = DockModel.dropPlaced(result.state, result.items, [], "pin:firefox", 2);
  assert.deepEqual(pinDropped.pins, [{ key: "pin:firefox", index: 2 }]);
  assert.deepEqual(pinDropped.state.windowPlacements, {});
});

test("dropPlaced does not change the state it is given", () => {
  const state = DockModel.newItemsState();
  const before = JSON.stringify(state);
  DockModel.dropPlaced(state, [{ key: "window:0xa" }, { key: "window:0xb" }], [], "window:0xb", 0);
  assert.equal(JSON.stringify(state), before);
});

test("a dropped Window Item shows where it was dropped on the next refresh", () => {
  const toplevels = [withClass("0xa", "firefox"), withClass("0xb", "alacritty"), withClass("0xc", "alacritty")];
  let result = DockModel.refreshItems(DockModel.newItemsState(), input(toplevels));
  const dropped = DockModel.dropPlaced(result.state, result.items, [], "window:0xc", 0);
  result = DockModel.refreshItems(dropped.state, input(toplevels, { pinPlacements: dropped.pins }));
  assert.equal(result.changed, true);
  assert.deepEqual(keys(result), ["window:0xc", "window:0xa", "window:0xb"]);
});

test("a Placed Window Item's position lasts only while its Window is open", () => {
  const toplevels = [withClass("0xa", "firefox"), withClass("0xb", "alacritty")];
  let result = DockModel.refreshItems(DockModel.newItemsState(), input(toplevels));
  const dropped = DockModel.dropPlaced(result.state, result.items, [], "window:0xb", 0);
  result = DockModel.refreshItems(dropped.state, input(toplevels));
  assert.deepEqual(result.state.windowPlacements, { "window:0xb": 0 });

  result = DockModel.refreshItems(result.state, input([toplevels[0]]));
  assert.deepEqual(result.state.windowPlacements, {});

  // The address coming back does not bring the position back.
  result = DockModel.refreshItems(result.state, input(toplevels));
  assert.deepEqual(keys(result), ["window:0xa", "window:0xb"]);
});

test("a Placed Pin's position is ignored while its Window Items are shown, and returns with the bare Pin", () => {
  const placements = [{ key: "pin:firefox", index: 1 }];
  let result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([withClass("0xa", "firefox"), withClass("0xb", "alacritty")], { pins: ["firefox"], pinPlacements: placements }),
  );
  assert.deepEqual(keys(result), ["window:0xa", "window:0xb"]);
  result = DockModel.refreshItems(result.state, input([withClass("0xb", "alacritty")], { pins: ["firefox"], pinPlacements: placements }));
  assert.deepEqual(keys(result), ["window:0xb", "pin:firefox"]);
});

test("a group's Placed position lasts until its last Window closes", () => {
  const two = [withClass("0xa", "firefox"), withClass("0xb", "firefox"), withClass("0xc", "alacritty")];
  let result = DockModel.refreshItems(DockModel.newItemsState(), input(two, { grouped: true }));
  const groupKey = result.items[0].key;
  assert.match(groupKey, /^group:/);
  const dropped = DockModel.dropPlaced(result.state, result.items, [], groupKey, 1);
  assert.equal(dropped.state.windowPlacements[groupKey], 1);
  result = DockModel.refreshItems(dropped.state, input(two, { grouped: true }));
  assert.equal(result.items[1].key, groupKey);
  result = DockModel.refreshItems(result.state, input([two[2]], { grouped: true }));
  assert.deepEqual(result.state.windowPlacements, {});
});

// The key format ----------------------------------------------------------

test("the Pin key is one format across DockModel and DockConfig", () => {
  const key = DockModel.pinKey("org.mozilla.firefox");
  assert.equal(DockModel.isPinKey(key), true);
  assert.equal(DockModel.isPinKey("window:0xa"), false);
  assert.equal(DockModel.isPinKey("group:app:firefox"), false);
  assert.equal(DockModel.isPinKey(undefined), false);

  // DockConfig persists exactly the keys DockModel calls Pin keys.
  const placements = effectiveView({
    placements: [
      { key, index: 1 },
      { key: "window:0xa", index: 2 },
      { key: "group:app:firefox", index: 3 },
    ],
  }).placements;
  assert.deepEqual(placements, [{ key, index: 1 }]);

  // And drops a Pin's position under the same key when it is dragged out.
  const entry = { pins: ["org.mozilla.firefox"], placements: [{ key, index: 1 }] };
  const next = applyIntent(entry, { type: "unpinAppFromDrag", appId: "org.mozilla.firefox" });
  assert.deepEqual(effectiveView(next).placements, []);
});

test("every Pin Item's key is a Pin key and no Window Item's is", () => {
  const result = DockModel.refreshItems(
    DockModel.newItemsState(),
    input([withClass("0xa", "alacritty")], { pins: ["firefox"] }),
  );
  for (const item of result.items) assert.equal(DockModel.isPinKey(item.key), item.kind === "pin");
});
