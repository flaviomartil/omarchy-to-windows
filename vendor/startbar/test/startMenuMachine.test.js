const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("../StartMenu.js");

// --- Helpers ----------------------------------------------------------------

const mkApp = (id, name) => ({ id, name: name || id, icon: id, entry: { id }, noDisplay: false });
const APPS = ["alacritty", "browser", "calc", "files", "gimp", "htop", "inkscape", "mail"].map((id) => mkApp(id));
const cat = S.catalog(APPS);

function ctxFor(over) {
  const o = over || {};
  const startPinIds = o.startPinIds || [];
  const query = o.query || "";
  return {
    command: o.command || "builtin",
    hoverOpen: o.hoverOpen !== undefined ? o.hoverOpen : true,
    results: S.filterApps(APPS, query),
    pinned: S.resolveApps(cat, startPinIds),
    recent: S.resolveApps(cat, o.recentIds || []),
    allFlat: cat.allFlat,
    letterRows: cat.letterRows,
    startPinIds,
    dockPinIds: o.dockPinIds || [],
  };
}

// Feed events through the machine like the QML view does: apply the state,
// remember every timer request and effect. `ctx` may be a function of the
// state so the results follow the typed query.
function feed(events, over, from) {
  let state = from || S.initial();
  const log = { timers: [], effects: [], handled: [] };
  for (const event of events) {
    const ctx = ctxFor(Object.assign({ query: state.query }, over));
    const result = S.transition(state, event, ctx);
    state = result.state;
    log.timers.push(result.timers);
    log.effects.push(...result.effects);
    log.handled.push(result.handled);
  }
  return Object.assign({ state }, log);
}

const effectTypes = (log) => log.effects.map((e) => e.type);
const key = (k) => ({ type: "key", key: k });
const type = (text) => ({ type: "queryChanged", text });
const hoverOpened = () => feed([{ type: "hoverOpenFired" }]);
const clickOpened = () => feed([{ type: "buttonClick" }]);
const leave = (pointerAround) => ({ type: "leaveFired", pointerAround: !!pointerAround });

// --- Open, close, toggle ----------------------------------------------------

test("a click on the Start button opens the menu in stay-open mode, a second click closes it", () => {
  const opened = clickOpened();
  assert.equal(opened.state.open, true);
  assert.equal(opened.state.hover, false);
  assert.deepEqual(effectTypes(opened), ["holdDock", "setQuery", "focusSearch"]);
  const closed = feed([{ type: "buttonClick" }], {}, opened.state);
  assert.equal(closed.state.open, false);
  assert.deepEqual(closed.effects, [{ type: "holdDock", held: false }]);
  assert.deepEqual(closed.timers[0], { leave: "stop" });
});

test("the keyboard command toggles the menu open and closed, and `close` only closes", () => {
  const toggled = feed([{ type: "command", action: "toggle" }]);
  assert.equal(toggled.state.open, true);
  assert.equal(toggled.state.hover, false);
  assert.equal(feed([{ type: "command", action: "toggle" }], {}, toggled.state).state.open, false);
  assert.equal(feed([{ type: "command", action: "close" }], {}, toggled.state).state.open, false);
  assert.equal(feed([{ type: "command", action: "close" }]).state.open, false);
});

test("the keyboard command on a hover-opened menu closes it, and the next one opens a real, stay-open menu", () => {
  const reopened = feed([{ type: "command", action: "toggle" }, { type: "command", action: "toggle" }], {}, hoverOpened().state);
  assert.equal(reopened.state.open, true);
  assert.equal(reopened.state.hover, false);
});

test("with a non-built-in startCommand the button and the keyboard command run it and never open the menu", () => {
  const over = { command: "omarchy-menu toggle apps" };
  const click = feed([{ type: "buttonClick" }], over);
  assert.equal(click.state.open, false);
  assert.deepEqual(click.effects, [{ type: "run", command: "omarchy-menu toggle apps" }]);
  assert.deepEqual(feed([{ type: "command", action: "toggle" }], over).effects, [{ type: "run", command: "omarchy-menu toggle apps" }]);
  assert.deepEqual(feed([{ type: "command", action: "close" }], over).effects, []);
  assert.equal(feed([{ type: "hoverOpenFired" }], over).state.open, false);
});

test("a click-away dismisses a stay-open menu", () => {
  assert.equal(feed([{ type: "dismiss" }], {}, clickOpened().state).state.open, false);
});

// --- Hover mode -------------------------------------------------------------

test("resting on the Start button arms the hover-open timer; leaving it stops that and arms the leave timer", () => {
  assert.deepEqual(feed([{ type: "buttonHover", hovered: true }]).timers[0], { hoverOpen: "start" });
  assert.deepEqual(feed([{ type: "buttonHover", hovered: false }]).timers[0], { hoverOpen: "stop", leave: "start" });
});

test("the hover-open timer opens the menu in hover mode, only when the setting is on and it is not already open", () => {
  const opened = hoverOpened();
  assert.equal(opened.state.open, true);
  assert.equal(opened.state.hover, true);
  assert.equal(feed([{ type: "hoverOpenFired" }], { hoverOpen: false }).state.open, false);
  const again = feed([{ type: "hoverOpenFired" }], {}, clickOpened().state);
  assert.equal(again.state.hover, false);
});

test("pointer leaving a hover-opened menu closes it after the delay, but a click-opened one stays", () => {
  const hovered = feed([{ type: "menuHover", hovered: false }], {}, hoverOpened().state);
  assert.deepEqual(hovered.timers[0], { leave: "start" });
  assert.equal(feed([leave(false)], {}, hovered.state).state.open, false);
  // the pointer came back before the timer fired
  assert.equal(feed([leave(true)], {}, hovered.state).state.open, true);

  const clicked = feed([{ type: "menuHover", hovered: false }, leave(false)], {}, clickOpened().state);
  assert.equal(clicked.state.open, true);
});

test("a click on the Start button does not make a hover-opened menu permanent, or close it", () => {
  const result = feed([{ type: "buttonClick" }], {}, hoverOpened().state);
  assert.equal(result.state.open, true);
  assert.equal(result.state.hover, true);
});

test("hover-open then a keystroke keeps the menu open after the pointer leaves", () => {
  const typed = feed([key("other")], {}, hoverOpened().state);
  assert.equal(typed.state.hover, false);
  assert.deepEqual(typed.effects, [{ type: "focusSearch", deferred: true }]);
  const after = feed([{ type: "menuHover", hovered: false }, leave(false)], {}, typed.state);
  assert.equal(after.state.open, true);
});

test("clicking the search box also ends hover mode; clicking elsewhere in the menu does not", () => {
  const pressed = feed([{ type: "searchPressed" }], {}, hoverOpened().state);
  assert.equal(pressed.state.hover, false);
  assert.deepEqual(pressed.effects, [{ type: "focusSearch", deferred: true }]);
  assert.equal(feed([{ type: "searchPressed" }], {}, clickOpened().state).effects.length, 0);
  const inside = feed([{ type: "showView", view: "all" }, { type: "toggleOverlay", kind: "power" }], {}, hoverOpened().state);
  assert.equal(inside.state.hover, true);
});

test("a hover-opened menu is not dismissed by click-away; a hover preview or another Item taking over closes it", () => {
  assert.equal(feed([{ type: "dismiss" }], {}, hoverOpened().state).state.open, true);
  const taken = feed([{ type: "itemHovered" }], {}, hoverOpened().state);
  assert.equal(taken.state.open, false);
  assert.deepEqual(taken.effects, [{ type: "holdDock", held: false }]);
});

test("another Item does not close a stay-open menu", () => {
  assert.equal(feed([{ type: "itemHovered" }], {}, clickOpened().state).state.open, true);
  assert.equal(feed([{ type: "itemHovered" }]).state.open, false);
});

// --- Reset ------------------------------------------------------------------

test("opening clears the search, selection, view, jump grid and overlay left from last time", () => {
  const dirty = Object.assign(S.initial(), {
    query: "fox", view: "all", letters: true, overlay: { kind: "power" },
    nav: { section: "pinned", index: 3 }, resultIndex: 4, allIndex: 7,
  });
  const reopened = feed([{ type: "buttonClick" }], {}, dirty);
  assert.deepEqual(reopened.state, Object.assign(S.initial(), { open: true }));
  assert.deepEqual(reopened.effects[1], { type: "setQuery", text: "" });
});

test("typing drops the overlay, arrow selection and jump grid and returns the highlight to the first result", () => {
  const ctxState = Object.assign(S.initial(), {
    open: true, overlay: { kind: "user" }, nav: { section: "recent", index: 1 }, resultIndex: 3, letters: true,
  });
  const typed = feed([type("b")], {}, ctxState).state;
  assert.equal(typed.query, "b");
  assert.equal(typed.overlay, null);
  assert.deepEqual(typed.nav, { section: "", index: -1 });
  assert.equal(typed.resultIndex, 0);
  assert.equal(typed.letters, false);
});

// --- Escape -----------------------------------------------------------------

test("Escape peels one layer at a time: overlay, jump grid, search, All apps, then the menu", () => {
  let state = clickOpened().state;
  state = feed([{ type: "showView", view: "all" }, { type: "letters", open: true }, type("a"),
    { type: "toggleOverlay", kind: "power" }], {}, state).state;
  // typing drops the jump grid, so put it back by hand to reach every layer
  state = Object.assign({}, state, { letters: true });
  assert.equal(state.overlay.kind, "power");

  const layers = [];
  for (let i = 0; i < 5; i++) {
    const step = feed([key("escape")], {}, state);
    assert.equal(step.handled[0], true);
    state = step.state;
    layers.push([state.overlay ? "overlay" : "", state.letters ? "letters" : "", state.query, state.view, state.open].join("|"));
  }
  assert.deepEqual(layers, [
    "|letters|a|all|true",
    "||a|all|true",
    "|||all|true",
    "|||home|true",
    "|||home|false",
  ]);
});

test("Escape clearing the search asks the view to empty the box", () => {
  const typed = feed([type("fi")], {}, clickOpened().state).state;
  const result = feed([key("escape")], {}, typed);
  assert.equal(result.state.query, "");
  assert.deepEqual(result.effects, [{ type: "setQuery", text: "" }]);
});

test("Escape on a hover-opened menu ends hover mode, then closes it", () => {
  const result = feed([key("escape")], {}, hoverOpened().state);
  assert.equal(result.state.open, false);
  assert.deepEqual(effectTypes(result), ["focusSearch", "holdDock"]);
});

// --- Enter ------------------------------------------------------------------

const launchedIds = (log) => log.effects.filter((e) => e.type === "launch").map((e) => e.app.id);

test("Enter in search launches the highlighted result, closes the menu and records it as recent", () => {
  const open = clickOpened().state;
  const result = feed([type("a"), key("down"), key("enter")], {}, open);
  // "a" matches alacritty (prefix) before calc / gimp / ... by rank, then alphabetically
  const expected = S.filterApps(APPS, "a")[1].id;
  assert.deepEqual(launchedIds(result), [expected]);
  assert.equal(result.state.open, false);
  assert.deepEqual(result.effects.find((e) => e.type === "apply"), { type: "apply", intent: { type: "pushRecentApp", appId: expected } });
});

test("Enter in search with no results does nothing but is still taken", () => {
  const result = feed([type("zzz"), key("enter")], {}, clickOpened().state);
  assert.equal(result.state.open, true);
  assert.deepEqual(launchedIds(result), []);
  assert.equal(result.handled[1], true);
});

test("Enter on the home screen launches the arrow-selected Pinned app, then the Recommended one", () => {
  const over = { startPinIds: ["calc", "files"], recentIds: ["mail", "gimp"] };
  const pinned = feed([key("down"), key("right"), key("enter")], over, clickOpened().state);
  assert.deepEqual(launchedIds(pinned), ["files"]);
  const recent = feed([key("down"), key("down"), key("enter")], over, clickOpened().state);
  assert.deepEqual(launchedIds(recent), ["mail"]);
});

test("Enter on the home screen with nothing selected launches nothing", () => {
  const result = feed([key("enter")], { startPinIds: ["calc"] }, clickOpened().state);
  assert.equal(result.state.open, true);
  assert.deepEqual(launchedIds(result), []);
});

test("Enter in All apps launches the highlighted row; Up/Down walk the A-Z list and ask the view to scroll", () => {
  const walked = feed([{ type: "showView", view: "all" }, key("down"), key("down"), key("down"), key("up")], {}, clickOpened().state);
  assert.equal(walked.state.allIndex, 1);
  assert.deepEqual(walked.effects.filter((e) => e.type === "scrollAll").map((e) => e.index), [0, 1, 2, 1]);
  const result = feed([key("enter")], {}, walked.state);
  assert.deepEqual(launchedIds(result), [cat.allFlat[1].id]);
});

test("All apps: Up/Down clamp to the list, and keys the list does not take go to the search box", () => {
  const state = feed([{ type: "showView", view: "all" }], {}, clickOpened().state).state;
  const top = feed([key("up")], {}, state);
  assert.equal(top.state.allIndex, 0);
  const bottom = feed(Array(20).fill(key("down")), {}, state);
  assert.equal(bottom.state.allIndex, cat.allFlat.length - 1);
  const left = feed([key("left")], {}, state);
  assert.equal(left.handled[0], false);
  assert.equal(feed([key("other")], {}, state).handled[0], false);
});

test("Up/Down in All apps do nothing while the jump grid is up", () => {
  const state = feed([{ type: "showView", view: "all" }, { type: "letters", open: true }], {}, clickOpened().state).state;
  assert.equal(feed([key("down")], {}, state).handled[0], false);
});

test("Down/Up in search move the highlight, clamped to the results", () => {
  const typed = feed([type("a")], {}, clickOpened().state);
  const count = S.filterApps(APPS, "a").length;
  assert.equal(feed(Array(count + 3).fill(key("down")), {}, typed.state).state.resultIndex, count - 1);
  assert.equal(feed([key("up")], {}, typed.state).state.resultIndex, 0);
});

test("clicking a tile, a result or an Open row launches it the same way", () => {
  const click = feed([{ type: "launch", app: APPS[3] }], {}, clickOpened().state);
  assert.deepEqual(launchedIds(click), ["files"]);
  assert.equal(click.state.open, false);
  const rows = S.overlayRows({ kind: "app", app: APPS[3] }, ctxFor());
  const chosen = feed([{ type: "choose", row: rows[2] }], {}, clickOpened().state);
  assert.deepEqual(launchedIds(chosen), ["files"]);
  assert.equal(chosen.state.open, false);
});

// --- Arrow selection (the Pinned / Recommended grids) -----------------------

const apps = (n) => Array.from({ length: n }, (_, i) => mkApp("p" + i));
function arrow(section, index, direction, pinned, recent) {
  const ctx = Object.assign(ctxFor(), { pinned: apps(pinned), recent: apps(recent) });
  const state = Object.assign(S.initial(), { open: true, nav: { section, index } });
  const next = S.transition(state, { type: "key", key: direction }, ctx).state.nav;
  return [next.section, next.index];
}

test("with nothing selected any arrow key selects the first pinned app, else the first recent", () => {
  assert.deepEqual(arrow("", -1, "down", 10, 4), ["pinned", 0]);
  assert.deepEqual(arrow("", -1, "right", 0, 4), ["recent", 0]);
  assert.deepEqual(arrow("", -1, "down", 0, 0), ["", -1]);
});

test("in the six-column Pinned grid, left/right step by one and up/down by a row", () => {
  assert.equal(S.PINNED_COLUMNS, 6);
  assert.deepEqual(arrow("pinned", 0, "right", 18, 0), ["pinned", 1]);
  assert.deepEqual(arrow("pinned", 1, "left", 18, 0), ["pinned", 0]);
  assert.deepEqual(arrow("pinned", 0, "left", 18, 0), ["pinned", 0]);
  assert.deepEqual(arrow("pinned", 17, "right", 18, 0), ["pinned", 17]);
  assert.deepEqual(arrow("pinned", 2, "down", 18, 0), ["pinned", 8]);
  assert.deepEqual(arrow("pinned", 8, "up", 18, 0), ["pinned", 2]);
  assert.deepEqual(arrow("pinned", 2, "up", 18, 0), ["pinned", 2]);
});

test("down from the last Pinned row enters Recommended, and up returns", () => {
  assert.deepEqual(arrow("pinned", 1, "down", 6, 4), ["recent", 0]);
  assert.deepEqual(arrow("pinned", 4, "down", 6, 4), ["recent", 1]);
  assert.deepEqual(arrow("pinned", 4, "down", 6, 1), ["recent", 0]);
  assert.deepEqual(arrow("pinned", 4, "down", 6, 0), ["pinned", 4]);
  assert.deepEqual(arrow("recent", 0, "up", 8, 4), ["pinned", 7]);
  assert.deepEqual(arrow("recent", 1, "up", 8, 4), ["pinned", 7]);
  assert.deepEqual(arrow("recent", 0, "up", 0, 4), ["recent", 0]);
});

test("in the two-column Recommended grid, left/right switch column and up/down step a row", () => {
  assert.equal(S.RECENT_COLUMNS, 2);
  assert.deepEqual(arrow("recent", 0, "right", 0, 4), ["recent", 1]);
  assert.deepEqual(arrow("recent", 1, "left", 0, 4), ["recent", 0]);
  assert.deepEqual(arrow("recent", 1, "right", 0, 4), ["recent", 1]);
  assert.deepEqual(arrow("recent", 0, "down", 0, 4), ["recent", 2]);
  assert.deepEqual(arrow("recent", 2, "down", 0, 4), ["recent", 2]);
});

test("a stale selection past the end is pulled back inside the lists", () => {
  assert.deepEqual(arrow("pinned", 30, "left", 5, 0), ["pinned", 3]);
  assert.deepEqual(arrow("recent", 9, "left", 0, 3), ["recent", 2]);
});

test("moving onto a Pinned app asks the view to scroll it into view; Recommended does not", () => {
  const ctx = Object.assign(ctxFor(), { pinned: apps(18), recent: apps(4) });
  const state = Object.assign(S.initial(), { open: true, nav: { section: "pinned", index: 2 } });
  assert.deepEqual(S.transition(state, key("down"), ctx).effects, [{ type: "scrollPinned", index: 8 }]);
  assert.deepEqual(S.transition(Object.assign({}, state, { nav: { section: "recent", index: 0 } }), key("right"), ctx).effects, []);
});

test("arrow keys in the home view are taken; in search they walk results and Left/Right fall through to the box", () => {
  const home = feed([key("left")], { startPinIds: ["calc"] }, clickOpened().state);
  assert.equal(home.handled[0], true);
  const typed = feed([type("a"), key("left")], {}, clickOpened().state);
  assert.equal(typed.handled[1], false);
});

// --- Catalog ----------------------------------------------------------------

test("catalog groups displayable apps under their first letter, non-letters under #, and indexes each letter", () => {
  const list = [
    { id: "b", name: "Beta" },
    { id: "a2", name: "avocado" },
    { id: "a1", name: "Alpha" },
    { id: "n", name: "7zip" },
    { id: "h", name: "Hidden", noDisplay: true },
  ];
  const c = S.catalog(list);
  assert.deepEqual(c.allFlat.map((a) => a.letter + a.id), ["#n", "Aa1", "Aa2", "Bb"]);
  assert.deepEqual(c.letterRows, { "#": 0, A: 1, B: 3 });
  assert.deepEqual(S.catalog(null).allFlat, []);
});

test("resolveApps keeps saved order and skips apps that are gone", () => {
  assert.deepEqual(S.resolveApps(cat, ["mail", "gone", "calc"]).map((a) => a.id), ["mail", "calc"]);
});

test("jumping to a letter closes the jump grid and scrolls All apps to its first row", () => {
  const state = feed([{ type: "showView", view: "all" }, { type: "letters", open: true }], {}, clickOpened().state).state;
  const result = feed([{ type: "jumpTo", letter: "C" }], {}, state);
  assert.equal(result.state.letters, false);
  assert.deepEqual(result.effects, [{ type: "scrollAll", index: cat.letterRows.C, position: "beginning" }]);
});

test("switching between home and All apps drops the selection; staying put keeps it", () => {
  const selected = Object.assign(S.initial(), { open: true, nav: { section: "pinned", index: 2 }, allIndex: 3 });
  const all = feed([{ type: "showView", view: "all" }], {}, selected).state;
  assert.deepEqual(all.nav, { section: "", index: -1 });
  assert.equal(all.allIndex, -1);
  assert.deepEqual(feed([{ type: "showView", view: "home" }], {}, selected).state.nav, { section: "pinned", index: 2 });
});

// --- Overlays ---------------------------------------------------------------

test("the account and power buttons toggle their own overlay and replace an app menu", () => {
  const state = clickOpened().state;
  const power = feed([{ type: "toggleOverlay", kind: "power" }], {}, state).state;
  assert.equal(power.overlay.kind, "power");
  assert.equal(feed([{ type: "toggleOverlay", kind: "power" }], {}, power).state.overlay, null);
  assert.equal(feed([{ type: "toggleOverlay", kind: "user" }], {}, power).state.overlay.kind, "user");
  const app = feed([{ type: "appMenu", app: APPS[0], x: 5, y: 6 }], {}, power).state;
  assert.deepEqual(app.overlay, { kind: "app", app: APPS[0], x: 5, y: 6 });
  assert.equal(feed([{ type: "closeOverlay" }], {}, app).state.overlay, null);
});

test("the power and account rows name the command each runs, and choosing one closes the menu", () => {
  const power = S.overlayRows({ kind: "power" }, ctxFor());
  assert.deepEqual(power.map((r) => r.label), ["Sleep", "Restart", "Shut down"]);
  assert.deepEqual(power.map((r) => r.action.command), ["systemctl suspend", "omarchy-system reboot", "omarchy-system shutdown"]);
  assert.deepEqual(power[2].action, { type: "run", command: "omarchy-system shutdown" });
  const user = S.overlayRows({ kind: "user" }, ctxFor());
  assert.deepEqual(user.map((r) => r.label), ["Lock", "Sign out"]);
  assert.deepEqual(user.map((r) => r.action.command), ["omarchy-system-lock", "omarchy-system logout"]);

  const open = feed([{ type: "toggleOverlay", kind: "power" }], {}, clickOpened().state).state;
  const chosen = feed([{ type: "choose", row: power[0] }], {}, open);
  assert.equal(chosen.state.open, false);
  assert.equal(chosen.state.overlay, null);
  assert.deepEqual(chosen.effects.slice(-1), [{ type: "run", command: "systemctl suspend" }]);
});

test("an app's menu words Pin/Unpin by where it is pinned; choosing a row keeps the menu open", () => {
  const app = { kind: "app", app: APPS[1] };
  const fresh = S.overlayRows(app, ctxFor());
  assert.deepEqual(fresh.map((r) => r.label), ["Pin to Start", "Pin to Dock", "Open"]);
  const pinned = S.overlayRows(app, ctxFor({ startPinIds: ["browser"], dockPinIds: ["browser"] }));
  assert.deepEqual(pinned.map((r) => r.label), ["Unpin from Start", "Unpin from Dock", "Open"]);
  assert.deepEqual(pinned[0].action, { type: "apply", intent: { type: "unpinStartApp", appId: "browser" } });
  assert.deepEqual(fresh[0].action, { type: "apply", intent: { type: "pinStartApp", appId: "browser" } });
  assert.deepEqual(pinned[1].action, { type: "togglePin", appId: "browser", pinned: true });

  const open = feed([{ type: "appMenu", app: APPS[1], x: 0, y: 0 }], {}, clickOpened().state).state;
  const chosen = feed([{ type: "choose", row: fresh[0] }], {}, open);
  assert.equal(chosen.state.open, true);
  assert.equal(chosen.state.overlay, null);
  assert.deepEqual(chosen.effects, [fresh[0].action]);
  assert.deepEqual(S.overlayRows(null, ctxFor()), []);
});

test("a Place closes the menu and hands off to the file manager", () => {
  const place = feed([{ type: "openPlace", path: "/home/u/Documents" }], {}, clickOpened().state);
  assert.equal(place.state.open, false);
  assert.deepEqual(place.effects.slice(-1), [{ type: "open", path: "/home/u/Documents" }]);
});

// --- Dock hold --------------------------------------------------------------

test("the Dock is held Revealed exactly while the menu is open", () => {
  const log = feed([{ type: "buttonClick" }, key("escape")]);
  assert.deepEqual(log.effects.filter((e) => e.type === "holdDock").map((e) => e.held), [true, false]);
  // closing a closed menu changes nothing and holds nothing
  assert.deepEqual(feed([{ type: "dismiss" }]).effects, []);
});

// --- Pinned-grid drag -------------------------------------------------------

const GRID = { width: 600, height: 300, cellWidth: 100, cellHeight: 100, contentY: 0 };
const dragOver = { startPinIds: ["a", "b", "c", "d"] };
const dragApps = ["a", "b", "c", "d"].map((id) => mkApp(id));
function drag(id, point, over, grid) {
  const ctx = Object.assign(ctxFor(), { pinned: dragApps.filter((a) => (over || dragOver.startPinIds).includes(a.id)), startPinIds: (over || dragOver.startPinIds) });
  let state = Object.assign(S.initial(), { open: true });
  const log = [];
  for (const event of [{ type: "pinDragStart", id }, { type: "pinDragMove", point, grid: grid || GRID }, { type: "pinDragEnd" }]) {
    const result = S.transition(state, event, ctx);
    if (event.type === "pinDragMove") log.push(result.state.drag.slot);
    state = result.state;
    log.push(...result.effects);
  }
  return { state, log };
}

test("dragging a pinned app names the slot under it, and releasing saves the reordered list", () => {
  const { state, log } = drag("a", { x: 250, y: 50 });
  assert.equal(log[0], 2);
  assert.deepEqual(log[1], { type: "apply", intent: { type: "reorderStartPins", order: ["b", "c", "a", "d"] } });
  assert.deepEqual(state.drag, { id: "", from: -1, slot: -1 });
});

test("the slot is clamped to the pins shown, and -1 a cell or more beyond the grid so nothing is saved", () => {
  assert.equal(drag("a", { x: 550, y: 250 }).log[0], 3);
  // just past an edge still names the nearest slot, the way the Dock's ends hold the icon
  assert.equal(drag("a", { x: -1, y: 50 }).log[0], 0);
  assert.equal(drag("a", { x: 650, y: 50 }).log[0], 3);
  const outside = drag("a", { x: -150, y: 50 });
  assert.equal(outside.log[0], -1);
  assert.equal(outside.log.length, 1);
  assert.equal(drag("a", { x: 50, y: 150 }).log[0], 3);
  assert.equal(drag("a", { x: 50, y: 150 }, null, Object.assign({}, GRID, { contentY: 100 })).log[0], 3);
});

test("a drag remembers the slot the app started in", () => {
  const ctx = Object.assign(ctxFor(), { pinned: dragApps, startPinIds: ["a", "b", "c", "d"] });
  const state = S.transition(Object.assign(S.initial(), { open: true }), { type: "pinDragStart", id: "c" }, ctx).state;
  assert.deepEqual(state.drag, { id: "c", from: 2, slot: 2 });
});

test("the ghost's top-left is held inside the grid and stops at the last pin", () => {
  const g = GRID; // 6 columns of 100 x 100; 4 pins: one row, last slot starts at x=300
  assert.deepEqual(S.clampPinGhost({ x: -40, y: -40 }, g, 4, 6), { x: 0, y: 0 });
  assert.deepEqual(S.clampPinGhost({ x: 120, y: 30 }, g, 4, 6), { x: 120, y: 0 });
  assert.deepEqual(S.clampPinGhost({ x: 590, y: 250 }, g, 4, 6), { x: 300, y: 0 });
  // 8 pins: a second row of two; the last slot is column 1 of row 1
  assert.deepEqual(S.clampPinGhost({ x: 590, y: 250 }, g, 8, 6), { x: 100, y: 100 });
  assert.deepEqual(S.clampPinGhost({ x: 590, y: 20 }, g, 8, 6), { x: 500, y: 20 });
  // scrolled: the grid's own y includes the scroll offset
  assert.deepEqual(S.clampPinGhost({ x: 0, y: -10 }, Object.assign({}, g, { contentY: 50 }), 8, 6), { x: 0, y: -10 });
  assert.deepEqual(S.clampPinGhost({ x: 0, y: -90 }, Object.assign({}, g, { contentY: 50 }), 8, 6), { x: 0, y: -50 });
});

test("tiles between the dragged app's slot and the target step aside, wrapping rows", () => {
  const g = GRID;
  const shifts = (from, slot, n) => Array.from({ length: n }, (_, i) => S.pinTileShift({ id: "x", from, slot }, i, g, 6));
  // 1 -> 3: tiles 2 and 3 move one slot left
  assert.deepEqual(shifts(1, 3, 5), [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: -100, y: 0 }, { x: -100, y: 0 }, { x: 0, y: 0 }]);
  // 3 -> 1: tiles 1 and 2 move one slot right
  assert.deepEqual(shifts(3, 1, 5), [{ x: 0, y: 0 }, { x: 100, y: 0 }, { x: 100, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]);
  // 4 -> 6: tile 6 moves from the start of row 1 to the end of row 0 (slot 5)
  assert.deepEqual(shifts(4, 6, 8)[6], { x: 500, y: -100 });
  assert.deepEqual(shifts(6, 5, 8)[5], { x: -500, y: 100 });
  // not dragging, or outside the grid: nothing moves
  assert.deepEqual(S.pinTileShift({ id: "", from: -1, slot: -1 }, 2, g, 6), { x: 0, y: 0 });
  assert.deepEqual(S.pinTileShift({ id: "x", from: 1, slot: -1 }, 2, g, 6), { x: 0, y: 0 });
});

test("dropping on the app's own slot, or dragging an app that is not pinned, saves nothing", () => {
  assert.equal(drag("a", { x: 50, y: 50 }).log.length, 1);
  assert.equal(drag("zzz", { x: 150, y: 50 }).log.length, 1);
});

test("the grid skips a pin whose app is gone, and the slot maps back to the saved list by id", () => {
  // "b" is saved but uninstalled, so the grid shows a, c, d
  const ctx = Object.assign(ctxFor(), { pinned: [dragApps[0], dragApps[2], dragApps[3]], startPinIds: ["a", "b", "c", "d"] });
  let state = Object.assign(S.initial(), { open: true });
  for (const event of [{ type: "pinDragStart", id: "d" }, { type: "pinDragMove", point: { x: 50, y: 50 }, grid: GRID }]) {
    state = S.transition(state, event, ctx).state;
  }
  assert.equal(state.drag.slot, 0);
  const end = S.transition(state, { type: "pinDragEnd" }, ctx);
  assert.deepEqual(end.effects, [{ type: "apply", intent: { type: "reorderStartPins", order: ["d", "a", "b", "c"] } }]);
});

test("a drag move with no drag in progress does nothing", () => {
  const result = S.transition(Object.assign(S.initial(), { open: true }), { type: "pinDragMove", point: { x: 1, y: 1 }, grid: GRID }, ctxFor());
  assert.deepEqual(result.state.drag, { id: "", from: -1, slot: -1 });
});

test("openCommand never lets a Place be read as an xdg-open option", () => {
  const { openCommand } = require("../StartMenu.js");
  assert.deepEqual(openCommand("/home/me/Documents"), ["xdg-open", "/home/me/Documents"]);
  assert.deepEqual(openCommand("--manual"), ["xdg-open", "./--manual"]);
  assert.deepEqual(openCommand("-x"), ["xdg-open", "./-x"]);
  assert.deepEqual(openCommand(undefined), ["xdg-open", ""]);
});
