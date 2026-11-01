const test = require("node:test");
const assert = require("node:assert/strict");
const DP = require("../DockPreview.js");

const a = { key: "window:a", window: { id: "0xa" } };
const b = { key: "window:b", window: { id: "0xb" } };
const ctx = { previewPeek: true, warp: false };

// Feed events through the machine the way the view does: state in, state out,
// collecting what it asked for.
function run(events, start, context) {
  let state = start || DP.initial();
  const timers = [];
  const effects = [];
  for (const event of events) {
    const r = DP.transition(state, event, context || ctx);
    state = r.state;
    timers.push(r.timers);
    effects.push(...r.effects);
  }
  return { state, timers, effects };
}

const hover = (item) => ({ type: "hoverStart", item, enabled: true, dragging: false });
const shown = (item) => run([hover(item), { type: "openFired" }]).state;

test("DockPreview has no Quickshell or QML imports, so Node can load it directly", () => {
  assert.equal(typeof DP.transition, "function");
});

// --- The Preview itself -----------------------------------------------------

test("a Preview opens after the open delay, not before", () => {
  const r = DP.transition(DP.initial(), hover(a), ctx);
  assert.deepEqual(r.timers, { leave: "stop", open: "start" });
  assert.equal(r.state.shown, null);
  assert.equal(DP.transition(r.state, { type: "openFired" }, ctx).state.shown, a);
});

test("moving to a neighbour while shown closes it and opens the neighbour's after the open delay", () => {
  const r = DP.transition(shown(a), hover(b), ctx);
  assert.equal(r.state.shown, null);
  assert.equal(r.state.hovered, b);
  assert.deepEqual(r.timers, { leave: "stop", open: "start" });
  assert.equal(DP.transition(r.state, { type: "openFired" }, ctx).state.shown, b);
});

test("re-entering the shown Item keeps its Preview up", () => {
  const r = DP.transition(shown(a), hover(a), ctx);
  assert.equal(r.state.shown, a);
  assert.deepEqual(r.timers, { leave: "stop" });
});

test("leaving cancels a pending open and arms the leave timer", () => {
  const s = DP.transition(DP.initial(), hover(a), ctx).state;
  const r = DP.transition(s, { type: "hoverEnd" }, ctx);
  assert.deepEqual(r.timers, { open: "stop", leave: "start" });
  assert.equal(DP.transition(r.state, { type: "leaveFired" }, ctx).state.shown, null);
});

test("hovering the Preview itself keeps it up; leaving it re-arms the leave timer", () => {
  assert.deepEqual(DP.transition(DP.initial(), { type: "previewHover", hovered: true }, ctx).timers, { leave: "stop" });
  assert.deepEqual(DP.transition(DP.initial(), { type: "previewHover", hovered: false }, ctx).timers, { leave: "start" });
});

test("no Preview while dragging, or for an Item that cannot have one", () => {
  const s = DP.initial();
  assert.deepEqual(DP.transition(s, { type: "hoverStart", item: a, enabled: true, dragging: true }, ctx), { state: s, timers: {}, effects: [] });
  assert.deepEqual(DP.transition(s, { type: "hoverStart", item: a, enabled: false, dragging: false }, ctx), { state: s, timers: {}, effects: [] });
});

test("an open timer firing with nothing hovered shows nothing", () => {
  assert.equal(DP.transition(DP.initial(), { type: "openFired" }, ctx).state.shown, null);
});

test("dismiss closes the Preview and stops both timers", () => {
  const r = DP.transition(shown(a), { type: "dismiss" }, ctx);
  assert.equal(r.state.shown, null);
  assert.deepEqual(r.timers, { open: "stop", leave: "stop" });
});

// --- The Preview menu holds the Preview up ---------------------------------

test("the leave timer firing while the Preview's menu is open leaves the Preview up", () => {
  const s = run([hover(a), { type: "openFired" }, { type: "menuVisible", visible: true, forPreview: true }]).state;
  assert.equal(DP.transition(s, { type: "leaveFired" }, ctx).state.shown, a);
});

test("closing the Preview's menu arms the leave timer so the Preview can go", () => {
  const open = run([hover(a), { type: "openFired" }, { type: "menuVisible", visible: true, forPreview: true }]).state;
  const r = DP.transition(open, { type: "menuVisible", visible: false, forPreview: true }, ctx);
  assert.deepEqual(r.timers, { leave: "start" });
  assert.equal(DP.transition(r.state, { type: "leaveFired" }, ctx).state.shown, null);
});

test("an Item menu neither holds the Preview nor arms the leave timer", () => {
  const open = run([hover(a), { type: "openFired" }, { type: "menuVisible", visible: true, forPreview: false }]).state;
  assert.equal(DP.transition(open, { type: "leaveFired" }, ctx).state.shown, null);
  assert.deepEqual(DP.transition(open, { type: "menuVisible", visible: false, forPreview: false }, ctx).timers, {});
});

test("an Item menu opened over a Preview menu, with no close between, does not hold the Preview up for good", () => {
  const s = run([
    hover(a), { type: "openFired" },
    { type: "menuVisible", visible: true, forPreview: true },
    { type: "menuVisible", visible: true, forPreview: false },
  ]).state;
  assert.equal(DP.transition(s, { type: "leaveFired" }, ctx).state.shown, null);
  assert.equal(DP.transition(s, { type: "thumbHover", window: { id: "0x1" }, hovered: true }, ctx).timers.peek, "start");
});

test("re-opening the Preview menu on another thumbnail (close, then open) still holds the Preview", () => {
  const r = run([
    hover(a), { type: "openFired" },
    { type: "menuVisible", visible: true, forPreview: true },
    { type: "menuVisible", visible: false, forPreview: true },
    { type: "menuVisible", visible: true, forPreview: true },
    { type: "leaveFired" },
  ]);
  assert.equal(r.state.shown, a);
});

// --- Peek -------------------------------------------------------------------

const w1 = { id: "0x1" };
const w2 = { id: "0x2" };
const peekHover = (window, hovered) => ({ type: "thumbHover", window, hovered });

test("hovering a thumbnail peeks it after the debounce, not at once", () => {
  const r = DP.transition(shown(a), peekHover(w1, true), ctx);
  assert.deepEqual(r.timers, { peekRestore: "stop", peek: "start" });
  assert.deepEqual(r.effects, []);
  const fired = DP.transition(r.state, { type: "peekFired" }, ctx);
  assert.deepEqual(fired.effects, [{ type: "peek", id: "0x1" }]);
  assert.equal(fired.state.peeking, true);
});

test("leaving a thumbnail restores after the restore delay, unless another is entered first", () => {
  let s = run([peekHover(w1, true), { type: "peekFired" }]).state;
  const left = DP.transition(s, peekHover(w1, false), ctx);
  assert.deepEqual(left.timers, { peek: "stop", peekRestore: "start" });
  // sweeping on to the next cell cancels the restore
  const entered = DP.transition(left.state, peekHover(w2, true), ctx);
  assert.equal(entered.timers.peekRestore, "stop");
  // and if nothing is entered, the restore timer asks for it
  const restored = DP.transition(left.state, { type: "peekRestoreFired" }, ctx);
  assert.deepEqual(restored.effects, [{ type: "restore" }]);
  assert.equal(restored.state.peeking, false);
});

test("a stale leave from the cell the pointer already left does not cancel the new cell's peek", () => {
  // Qt can report the next cell's enter before the previous cell's leave.
  const s = run([peekHover(w1, true), peekHover(w2, true)]).state;
  const stale = DP.transition(s, peekHover(w1, false), ctx);
  assert.deepEqual(stale.timers, {});
  assert.equal(DP.transition(stale.state, { type: "peekFired" }, ctx).effects[0].id, "0x2");
});

test("with Peek off, hovering a thumbnail does nothing", () => {
  const off = { previewPeek: false, warp: false };
  assert.deepEqual(DP.transition(shown(a), peekHover(w1, true), off), { state: shown(a), timers: {}, effects: [] });
});

test("the peek timer firing with no target peeks nothing", () => {
  assert.deepEqual(DP.transition(shown(a), { type: "peekFired" }, ctx).effects, []);
});

test("hovering a thumbnail while its Preview menu is open leaves the peek alone", () => {
  const s = run([hover(a), { type: "openFired" }, { type: "menuVisible", visible: true, forPreview: true }]).state;
  assert.deepEqual(DP.transition(s, peekHover(w2, true), ctx), { state: s, timers: {}, effects: [] });
});

// --- Click, commit and restore ---------------------------------------------

test("picking a thumbnail commits the peek, then focuses, then closes the Preview", () => {
  const s = run([hover(a), { type: "openFired" }, peekHover(w1, true), { type: "peekFired" }]).state;
  const r = DP.transition(s, { type: "thumbPicked", window: w1 }, { previewPeek: true, warp: true });
  assert.deepEqual(r.effects, [{ type: "commit" }, { type: "focus", id: "0x1", warp: true }]);
  assert.equal(r.state.shown, null);
  assert.equal(r.state.peeking, false);
  assert.deepEqual(r.timers, { peek: "stop", open: "stop", leave: "stop" });
});

test("the Preview closing after a pick does not restore what the pick just committed", () => {
  const s = run([hover(a), { type: "openFired" }, peekHover(w1, true), { type: "peekFired" }, { type: "thumbPicked", window: w1 }]).state;
  assert.deepEqual(DP.transition(s, { type: "previewClosed" }, ctx).effects, []);
});

test("the Preview closing mid-peek restores", () => {
  const s = run([hover(a), { type: "openFired" }, peekHover(w1, true), { type: "peekFired" }]).state;
  const r = DP.transition(s, { type: "previewClosed" }, ctx);
  assert.deepEqual(r.effects, [{ type: "restore" }]);
  assert.equal(r.state.peeking, false);
  assert.equal(r.state.peekTarget, null);
  assert.deepEqual(r.timers, { peek: "stop", peekRestore: "stop" });
});

test("the Preview closing with nothing peeked starts no restore, even with Peek on", () => {
  assert.deepEqual(DP.transition(shown(a), { type: "previewClosed" }, ctx).effects, []);
});

test("a peek still gets put back after Peek is turned off mid-hover", () => {
  const s = run([hover(a), { type: "openFired" }, peekHover(w1, true), { type: "peekFired" }]).state;
  const off = { previewPeek: false, warp: false };
  assert.deepEqual(DP.transition(s, { type: "previewClosed" }, off).effects, [{ type: "restore" }]);
});

// --- Right click on a thumbnail --------------------------------------------

test("opening the menu on the peeked Window leaves the peek as it is", () => {
  const s = run([peekHover(w1, true), { type: "peekFired" }]).state;
  const r = DP.transition(s, { type: "thumbMenu", windowId: "0x1" }, ctx);
  assert.deepEqual(r.effects, []);
  assert.equal(r.state.peeking, true);
  assert.deepEqual(r.timers, { peek: "stop", peekRestore: "stop" });
  assert.equal(r.state.peekTarget, null);
});

test("opening the menu on a different Window puts the other Window's peek back first", () => {
  const s = run([peekHover(w1, true), { type: "peekFired" }]).state;
  const r = DP.transition(s, { type: "thumbMenu", windowId: "0x2" }, ctx);
  assert.deepEqual(r.effects, [{ type: "restore" }]);
  assert.equal(r.state.peeking, false);
});

test("opening the menu with nothing peeked asks for nothing", () => {
  assert.deepEqual(DP.transition(shown(a), { type: "thumbMenu", windowId: "0x2" }, ctx).effects, []);
});

test("choosing a state row in the menu commits the peek (the Window stays focused)", () => {
  const s = run([peekHover(w1, true), { type: "peekFired" }, { type: "thumbMenu", windowId: "0x1" }]).state;
  const r = DP.transition(s, { type: "menuRowChosen" }, ctx);
  assert.deepEqual(r.effects, [{ type: "commit" }]);
  assert.equal(r.state.peeking, false);
});

test("choosing a row when nothing is peeked still clears any stale state file", () => {
  assert.deepEqual(DP.transition(DP.initial(), { type: "menuRowChosen" }, ctx).effects, [{ type: "commit" }]);
});

// --- What is live -----------------------------------------------------------

const win = (id) => ({ id });

test("liveItem finds the shown Item's current form by Window id, since a Group Item's key changes", () => {
  const shownGroup = { kind: "window", key: "group:app", windows: [win("1"), win("2")] };
  const nowOne = { kind: "window", key: "window:1", window: win("1") };
  assert.equal(DP.liveItem(shownGroup, [{ kind: "pin", key: "pin:x" }, nowOne]), nowOne);
});

test("liveItem is null once every shown Window is gone, or when nothing is shown", () => {
  const shownItem = { kind: "window", key: "window:1", window: win("1") };
  assert.equal(DP.liveItem(shownItem, [{ kind: "window", key: "window:9", window: win("9") }]), null);
  assert.equal(DP.liveItem(null, [shownItem]), null);
});

test("windowIds returns the previous array while the set of Windows is unchanged, so the cells are not rebuilt", () => {
  const prev = ["1", "2"];
  assert.equal(DP.windowIds(prev, [win("1"), win("2")]), prev);
  assert.deepEqual(DP.windowIds(prev, [win("1")]), ["1"]);
});
