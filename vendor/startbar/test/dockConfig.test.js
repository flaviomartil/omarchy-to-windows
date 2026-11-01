const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  DEFAULT_ICON_SIZE,
  DEFAULT_REVEAL_DELAY_MS,
  DEFAULT_HIDE_DELAY_MS,
  findPluginEntry,
  effectiveView,
  applyIntent,
} = require("../DockConfig.js");

const effectiveSettings = (entry) => effectiveView(entry).settings;
const effectivePins = (entry) => effectiveView(entry).pins;
const effectivePlacements = (entry) => effectiveView(entry).placements;

const PLUGIN_ID = "io.github.bmaltais.startbar";

test("DockConfig has no Quickshell or QML imports, so Node can load it directly", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "DockConfig.js"),
    "utf8",
  );
  assert.doesNotMatch(source, /^\s*import\s/m);
  assert.equal(typeof findPluginEntry, "function");
  assert.equal(typeof effectiveView, "function");
  assert.equal(typeof applyIntent, "function");
});

test("findPluginEntry finds the Dock's own entry among other plugins", () => {
  const shellConfig = {
    plugins: [{ id: "axel.window-close-buttons" }, { id: PLUGIN_ID, iconSize: 64 }],
  };

  const entry = findPluginEntry(shellConfig, PLUGIN_ID);

  assert.deepEqual(entry, { id: PLUGIN_ID, iconSize: 64 });
});

test("findPluginEntry returns null when the Dock has no entry", () => {
  const shellConfig = { plugins: [{ id: "axel.window-close-buttons" }] };

  assert.equal(findPluginEntry(shellConfig, PLUGIN_ID), null);
});

test("findPluginEntry returns null when the config has no plugins array", () => {
  assert.equal(findPluginEntry({}, PLUGIN_ID), null);
  assert.equal(findPluginEntry(null, PLUGIN_ID), null);
});

test("the view's settings defaults to 48px icons, a 200ms reveal delay, and a 300ms hide delay when the entry has no values", () => {
  assert.deepEqual(effectiveSettings(null), {
    iconSize: DEFAULT_ICON_SIZE,
    revealDelayMs: DEFAULT_REVEAL_DELAY_MS,
    hideDelayMs: DEFAULT_HIDE_DELAY_MS,
  });
  assert.deepEqual(effectiveSettings({ id: PLUGIN_ID }), {
    iconSize: DEFAULT_ICON_SIZE,
    revealDelayMs: DEFAULT_REVEAL_DELAY_MS,
    hideDelayMs: DEFAULT_HIDE_DELAY_MS,
  });
});

test("the view's settings uses the entry's own values when present", () => {
  const settings = effectiveSettings({
    id: PLUGIN_ID,
    iconSize: 64,
    revealDelayMs: 100,
    hideDelayMs: 500,
  });

  assert.deepEqual(settings, {
    iconSize: 64,
    revealDelayMs: 100,
    hideDelayMs: 500,
  });
});

test("the view's settings falls back to defaults for a hand-edited value that isn't a usable positive number", () => {
  const settings = effectiveSettings({
    iconSize: "not-a-number",
    revealDelayMs: -50,
    hideDelayMs: 0,
  });

  assert.deepEqual(settings, {
    iconSize: DEFAULT_ICON_SIZE,
    revealDelayMs: DEFAULT_REVEAL_DELAY_MS,
    hideDelayMs: DEFAULT_HIDE_DELAY_MS,
  });
});

test("the view's pins is empty when the entry has no Pins", () => {
  assert.deepEqual(effectivePins(null), []);
  assert.deepEqual(effectivePins({ id: PLUGIN_ID }), []);
});

test("the view's pins passes through a well-formed Pins list in its persisted order", () => {
  const pins = effectivePins({ id: PLUGIN_ID, pins: ["firefox", "alacritty"] });

  assert.deepEqual(pins, ["firefox", "alacritty"]);
});

test("the view's pins drops a hand-edited entry that isn't a usable App id", () => {
  const pins = effectivePins({
    pins: ["firefox", 42, null, "", "alacritty"],
  });

  assert.deepEqual(pins, ["firefox", "alacritty"]);
});

test("the view's pins dedupes a repeated App id, keeping its first slot", () => {
  const pins = effectivePins({ pins: ["firefox", "alacritty", "firefox"] });

  assert.deepEqual(pins, ["firefox", "alacritty"]);
});

test("the view's placements is empty when the entry has no placements", () => {
  assert.deepEqual(effectivePlacements(null), []);
  assert.deepEqual(effectivePlacements({ id: PLUGIN_ID }), []);
});

test("the view's placements passes through a well-formed Placed Pin entry", () => {
  const placements = effectivePlacements({
    id: PLUGIN_ID,
    placements: [{ key: "pin:firefox", index: 2 }],
  });

  assert.deepEqual(placements, [{ key: "pin:firefox", index: 2 }]);
});

test("the view's placements drops an entry whose key isn't a Placed Pin, since a Placed Window Item is never persisted", () => {
  const placements = effectivePlacements({
    placements: [{ key: "window:w1", index: 0 }, { key: "pin:firefox", index: 1 }],
  });

  assert.deepEqual(placements, [{ key: "pin:firefox", index: 1 }]);
});

test("the view's placements drops a hand-edited entry with no usable key or a negative/non-numeric index", () => {
  const placements = effectivePlacements({
    placements: [
      { key: "pin:firefox", index: "not-a-number" },
      { key: "pin:alacritty", index: -1 },
      { key: 42, index: 0 },
      null,
      { key: "pin:btop", index: 3 },
    ],
  });

  assert.deepEqual(placements, [{ key: "pin:btop", index: 3 }]);
});

test("the view's placements dedupes a repeated key, keeping its first entry", () => {
  const placements = effectivePlacements({
    placements: [{ key: "pin:firefox", index: 0 }, { key: "pin:firefox", index: 5 }],
  });

  assert.deepEqual(placements, [{ key: "pin:firefox", index: 0 }]);
});

test("an intent folds onto the entry without dropping keys it doesn't mention", () => {
  const entry = { id: PLUGIN_ID, iconSize: 48, pins: ["firefox"] };

  const next = applyIntent(entry, { type: "setSetting", key: "iconSize", value: 64 });

  assert.deepEqual(next, { id: PLUGIN_ID, iconSize: 64, pins: ["firefox"] });
  assert.equal(entry.iconSize, 48);
});

test("an intent starts from an empty object when there is no existing entry", () => {
  assert.deepEqual(applyIntent(null, { type: "setSetting", key: "iconSize", value: 64 }), { iconSize: 64 });
});

test("the view carries Start pins, recent apps and Start places, defaulted and cleaned", () => {
  const view = effectiveView({
    pins: ["a", "b"],
    startPins: ["x", "y", "x", 3, ""],
    recentApps: ["r", "r", 1, "s"],
    startPlaces: ["~/p", "~/p", 5, ""],
  });
  assert.deepEqual(view.startPins, ["x", "y"]);
  assert.deepEqual(view.recentApps, ["r", "s"]);
  assert.deepEqual(view.startPlaces, ["~/p"]);
});

test("the Start menu starts out showing the Dock's Pins until it has a list of its own", () => {
  assert.deepEqual(effectiveView({ pins: ["d", "d", "e"] }).startPins, ["d", "e"]);
  assert.deepEqual(effectiveView(null).startPins, []);
  assert.deepEqual(effectiveView({ pins: ["d"], startPins: [] }).startPins, []);
});

test("an unset startPlaces stays null so the Start menu uses the XDG folders; recents default to none", () => {
  const view = effectiveView({});
  assert.equal(view.startPlaces, null);
  assert.deepEqual(view.recentApps, []);
  assert.deepEqual(effectiveView({ startPlaces: [] }).startPlaces, []);
});

test("garbage in the entry is defaulted rather than thrown on", () => {
  for (const entry of [undefined, null, 5, "x", [], { pins: "firefox", placements: 3, startPins: {}, recentApps: 1, startPlaces: "x", iconSize: "big" }]) {
    const view = effectiveView(entry);
    assert.deepEqual(view.pins, []);
    assert.deepEqual(view.placements, []);
    assert.deepEqual(view.startPins, []);
    assert.deepEqual(view.recentApps, []);
    assert.equal(view.startPlaces, null);
    assert.equal(view.settings.iconSize, DEFAULT_ICON_SIZE);
    assert.equal(view.taskbar.autoHide, false);
  }
});

test("intents on a garbage entry still produce a usable entry", () => {
  const next = applyIntent({ pins: "firefox", placements: 3 }, { type: "pinApp", appId: "alacritty" });
  assert.deepEqual(next.pins, ["alacritty"]);
});

test("pinApp appends an App id when it isn't already pinned", () => {
  assert.deepEqual(applyIntent({ pins: ["alacritty"] }, { type: "pinApp", appId: "firefox" }).pins, ["alacritty", "firefox"]);
});

test("pinApp leaves the Pins unchanged for an App already pinned", () => {
  assert.deepEqual(applyIntent({ pins: ["alacritty", "firefox"] }, { type: "pinApp", appId: "firefox" }).pins, ["alacritty", "firefox"]);
});

test("unpinApp removes an App id, and is a no-op for an App that isn't pinned", () => {
  assert.deepEqual(applyIntent({ pins: ["alacritty", "firefox"] }, { type: "unpinApp", appId: "firefox" }).pins, ["alacritty"]);
  assert.deepEqual(applyIntent({ pins: ["alacritty"] }, { type: "unpinApp", appId: "firefox" }).pins, ["alacritty"]);
});

test("an intent without a usable App id changes nothing", () => {
  const entry = { pins: ["a"], startPins: ["a"], recentApps: ["a"] };
  for (const type of ["pinApp", "unpinApp", "unpinAppFromDrag", "pinStartApp", "unpinStartApp", "pushRecentApp"]) {
    for (const appId of [undefined, "", 3]) assert.deepEqual(applyIntent(entry, { type, appId }), entry, `${type} ${appId}`);
  }
  assert.deepEqual(applyIntent(entry, { type: "nonsense" }), entry);
  assert.deepEqual(applyIntent(entry, null), entry);
});

test("setPlacements records the Placed positions of Pins, replacing the old ones", () => {
  const entry = { placements: [{ key: "pin:firefox", index: 0 }] };
  const next = applyIntent(entry, {
    type: "setPlacements",
    placements: [{ key: "pin:alacritty", index: 1 }, { key: "pin:firefox", index: 5 }],
  });
  assert.deepEqual(next.placements, [{ key: "pin:alacritty", index: 1 }, { key: "pin:firefox", index: 5 }]);
});

test("setPlacements never persists a Window Item's position", () => {
  const next = applyIntent({}, { type: "setPlacements", placements: [{ key: "window:w1", index: 2 }] });
  assert.deepEqual(next.placements || [], []);
});

test("unpinAppFromDrag unpins the App and drops its Pin's Placed position in one entry, leaving other Pins and positions", () => {
  const entry = {
    pins: ["firefox", "alacritty"],
    placements: [{ key: "pin:firefox", index: 0 }, { key: "pin:alacritty", index: 1 }],
  };

  const next = applyIntent(entry, { type: "unpinAppFromDrag", appId: "firefox" });

  assert.deepEqual(next.pins, ["alacritty"]);
  assert.deepEqual(next.placements, [{ key: "pin:alacritty", index: 1 }]);
});

test("unpinAppFromDrag for an App that was never Placed only unpins it", () => {
  const next = applyIntent({ pins: ["firefox"], placements: [] }, { type: "unpinAppFromDrag", appId: "firefox" });
  assert.deepEqual(next, { pins: [], placements: [] });
});

test("two intents in one tick both survive when the second folds onto the first's result", () => {
  const entry = { id: PLUGIN_ID, pins: ["firefox"] };

  const first = applyIntent(entry, { type: "pinApp", appId: "alacritty" });
  const second = applyIntent(first, { type: "setPlacements", placements: [{ key: "pin:alacritty", index: 0 }] });

  assert.deepEqual(second.pins, ["firefox", "alacritty"]);
  assert.deepEqual(second.placements, [{ key: "pin:alacritty", index: 0 }]);
  assert.equal(second.id, PLUGIN_ID);
});

test("pinStartApp and unpinStartApp work on the Start menu's list, starting from the Pins when it has none of its own", () => {
  const pinned = applyIntent({ pins: ["d"] }, { type: "pinStartApp", appId: "x" });
  assert.deepEqual(pinned.startPins, ["d", "x"]);
  assert.deepEqual(pinned.pins, ["d"]);
  assert.deepEqual(applyIntent(pinned, { type: "pinStartApp", appId: "x" }).startPins, ["d", "x"]);
  assert.deepEqual(applyIntent(pinned, { type: "unpinStartApp", appId: "d" }).startPins, ["x"]);
});

test("reorderStartPins replaces the Start menu's list with the cleaned new order", () => {
  const next = applyIntent({ startPins: ["a", "b"] }, { type: "reorderStartPins", order: ["b", "a", "b", 3] });
  assert.deepEqual(next.startPins, ["b", "a"]);
});

test("pushRecentApp moves an App to the front, de-duplicates and caps the list at six", () => {
  assert.deepEqual(applyIntent({ recentApps: ["a", "b"] }, { type: "pushRecentApp", appId: "c" }).recentApps, ["c", "a", "b"]);
  assert.deepEqual(applyIntent({ recentApps: ["a", "b", "c"] }, { type: "pushRecentApp", appId: "b" }).recentApps, ["b", "a", "c"]);
  assert.deepEqual(applyIntent({}, { type: "pushRecentApp", appId: "a" }).recentApps, ["a"]);
  const full = applyIntent({ recentApps: ["1", "2", "3", "4", "5", "6"] }, { type: "pushRecentApp", appId: "7" });
  assert.deepEqual(full.recentApps, ["7", "1", "2", "3", "4", "5"]);
});

test("setSettings puts a setting back to its default when its patched value is undefined or null", () => {
  const entry = { iconSize: 64, alignment: "left" };
  assert.deepEqual(applyIntent(entry, { type: "setSettings", patch: { iconSize: undefined } }), { alignment: "left" });
  assert.deepEqual(applyIntent(entry, { type: "setSetting", key: "alignment", value: null }), { iconSize: 64 });
});

test("resetSettings puts every setting back to its default but leaves Pins, Placed positions, Start pins and recents alone", () => {
  const entry = {
    id: PLUGIN_ID,
    iconSize: 64,
    alignment: "left",
    startPlaces: ["~/a"],
    startCommand: "builtin",
    pins: ["firefox"],
    placements: [{ key: "pin:firefox", index: 1 }],
    startPins: ["x"],
    recentApps: ["y"],
  };

  const next = applyIntent(entry, { type: "resetSettings" });

  assert.deepEqual(next, {
    id: PLUGIN_ID,
    pins: ["firefox"],
    placements: [{ key: "pin:firefox", index: 1 }],
    startPins: ["x"],
    recentApps: ["y"],
  });
  assert.deepEqual(effectiveView(next).settings, effectiveView(null).settings);
  assert.deepEqual(effectiveView(next).taskbar, effectiveView(null).taskbar);
});

test("a bar menu row's patch applies through setSettings", () => {
  const next = applyIntent({ alignment: "center", iconSize: 64 }, { type: "setSettings", patch: { alignment: "left" } });
  assert.deepEqual(next, { alignment: "left", iconSize: 64 });
});
