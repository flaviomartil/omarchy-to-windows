const test = require("node:test");
const assert = require("node:assert/strict");
const DI = require("../DockInteraction.js");

test("DockInteraction has no Quickshell or QML imports, so Node can load it directly", () => {
  assert.equal(typeof DI.setRevealFlag, "function");
});

test("the first held flag arms the reveal timer and stops the hide timer", () => {
  const r = DI.setRevealFlag(DI.initialReveal(), "strip", true);
  assert.deepEqual(r.timers, { hide: "stop", reveal: "start" });
  assert.equal(r.state.revealed, false);
  assert.equal(DI.revealTimerFired(r.state).state.revealed, true);
});

test("a second flag while one is held leaves the timers alone", () => {
  let s = DI.setRevealFlag(DI.initialReveal(), "strip", true).state;
  const r = DI.setRevealFlag(s, "dock", true);
  assert.deepEqual(r.timers, {});
  // dropping one of two doesn't start hiding
  s = r.state;
  assert.deepEqual(DI.setRevealFlag(s, "strip", false).timers, {});
});

test("when the last flag drops, reveal stops and hide starts, then Hidden", () => {
  let s = DI.revealTimerFired(DI.setRevealFlag(DI.initialReveal(), "dock", true).state).state;
  const r = DI.setRevealFlag(s, "dock", false);
  assert.deepEqual(r.timers, { reveal: "stop", hide: "start" });
  assert.equal(DI.hideTimerFired(r.state).state.revealed, false);
});

test("holding again while already Revealed only stops the hide timer", () => {
  let s = DI.revealTimerFired(DI.setRevealFlag(DI.initialReveal(), "dock", true).state).state;
  s = DI.setRevealFlag(s, "dock", false).state;
  assert.deepEqual(DI.setRevealFlag(s, "bar", true).timers, { hide: "stop" });
});

test("menu and drag hold the Dock up with no hover at all", () => {
  let s = DI.setRevealFlag(DI.initialReveal(), "menu", true).state;
  assert.equal(DI.isHeld(s), true);
  s = DI.setRevealFlag(s, "drag", true).state;
  s = DI.setRevealFlag(s, "menu", false).state;
  assert.equal(DI.isHeld(s), true);
  assert.deepEqual(DI.setRevealFlag(s, "drag", false).timers, { reveal: "stop", hide: "start" });
});

test("each holder of the Dock keeps its own hold: one closing does not drop another's", () => {
  let s = DI.setRevealFlag(DI.initialReveal(), "barMenu", true).state;
  s = DI.setRevealFlag(s, "startMenu", true).state;
  s = DI.setRevealFlag(s, "startMenu", false).state;
  assert.equal(DI.isHeld(s), true);
  assert.deepEqual(DI.setRevealFlag(s, "barMenu", false).timers, { reveal: "stop", hide: "start" });
});

test("setting a flag to its current value, or an unknown flag, changes nothing", () => {
  const s = DI.initialReveal();
  assert.deepEqual(DI.setRevealFlag(s, "strip", false).timers, {});
  assert.deepEqual(DI.setRevealFlag(s, "nope", true).timers, {});
  assert.equal(DI.isHeld(DI.setRevealFlag(s, "nope", true).state), false);
});

const row = { x: 100, y: 500, width: 400, height: 60 };

test("dragMove names the slot under the ghost's centre, never past the first or last Item", () => {
  const d = DI.dragStart("pin:x", 0);
  // 4 Items, 50px apart from x=100: slots start at 100, 150, 200, 250
  assert.equal(DI.dragMove(d, { x: 100 + 10, y: 530 }, row, 50, 40, 4).to, 0);
  assert.equal(DI.dragMove(d, { x: 100 + 2 * 50 + 10, y: 530 }, row, 50, 40, 4).to, 2);
  assert.equal(DI.dragMove(d, { x: 100 + 3 * 50 + 30, y: 530 }, row, 50, 40, 4).to, 3);
  assert.equal(DI.dragMove(d, { x: 100 + 900, y: 530 }, row, 50, 40, 4).to, 3);
  assert.equal(DI.dragMove(d, { x: 100 - 300, y: 530 }, row, 50, 40, 4).to, 0);
  assert.equal(DI.dragMove(d, { x: 300, y: 530 }, row, 0, 40, 4).to, 0);
});

test("a drag starts on its own slot, so dropping it unmoved lands where it was", () => {
  assert.equal(DI.finalIndex(DI.dragStart("pin:b", 1)), 1);
  const right = DI.dragMove(DI.dragStart("pin:a", 0), { x: 100 + 3 * 50 + 25, y: 530 }, row, 50, 40, 4);
  assert.equal(DI.finalIndex(right), 3);
  assert.deepEqual(DI.dragDrop(right, { x: 275, y: 530 }, row, 40, { pinned: true }), { action: "reorder", index: 3 });
  const left = DI.dragMove(DI.dragStart("pin:d", 3), { x: 100 + 60, y: 530 }, row, 50, 40, 4);
  assert.equal(DI.finalIndex(left), 1);
});

test("the dragged Item's slot holds still while the Items between it and the target step aside", () => {
  const right = DI.dragMove(DI.dragStart("a", 1), { x: 100 + 3 * 50 + 25, y: 530 }, row, 50, 40, 5);
  assert.deepEqual([0, 1, 2, 3, 4].map((i) => DI.slotShift(right, i, 50)), [0, 0, -50, -50, 0]);
  const left = DI.dragMove(DI.dragStart("d", 3), { x: 100 + 25, y: 530 }, row, 50, 40, 5);
  assert.deepEqual([0, 1, 2, 3, 4].map((i) => DI.slotShift(left, i, 50)), [50, 50, 50, 0, 0]);
  assert.deepEqual([0, 1, 2].map((i) => DI.slotShift(DI.dragStart("a", 1), i, 50)), [0, 0, 0]);
  assert.equal(DI.slotShift(DI.initialDrag(), 2, 50), 0);
});

test("the ghost's left edge stops at the first and last slot while the pointer goes on", () => {
  // 4 Items from x=100, 50px apart: the last slot starts at 250
  assert.equal(DI.clampGhostX(10, row, 50, 4), 100);
  assert.equal(DI.clampGhostX(180, row, 50, 4), 180);
  assert.equal(DI.clampGhostX(900, row, 50, 4), 250);
  assert.equal(DI.clampGhostX(300, row, 50, 0), 100);
});

test("a drag is outside only once it leaves the bar vertically, by half an icon", () => {
  const d = DI.dragStart("pin:x", 1);
  assert.equal(DI.dragMove(d, { x: 300, y: 530 }, row, 50, 40, 5).outside, false);
  assert.equal(DI.dragMove(d, { x: 300, y: 500 - 20 }, row, 50, 40, 5).outside, false);
  assert.equal(DI.dragMove(d, { x: 300, y: 500 - 21 }, row, 50, 40, 5).outside, true);
  assert.equal(DI.dragMove(d, { x: 300, y: 560 + 21 }, row, 50, 40, 5).outside, true);
  // sideways it only stops at the end of the row
  assert.equal(DI.dragMove(d, { x: 100 + 400 + 300, y: 530 }, row, 50, 40, 5).outside, false);
});

test("dragMove with no drag in progress returns the idle drag unchanged", () => {
  const idle = DI.initialDrag();
  assert.equal(DI.dragMove(idle, { x: 0, y: 0 }, row, 50, 40, 5), idle);
  assert.equal(DI.dragActive(idle), false);
});

test("dropping inside reorders to the slot it shows", () => {
  const d = DI.dragMove(DI.dragStart("pin:x", 3), { x: 100 + 2 * 50 + 25, y: 530 }, row, 50, 40, 5);
  assert.deepEqual(DI.dragDrop(d, { x: 225, y: 530 }, row, 40, { pinned: true }), { action: "reorder", index: 2 });
});

test("dropping outside unpins a pinned Item and snaps an unpinned one back", () => {
  const d = DI.dragStart("pin:x", 1);
  const far = { x: 300, y: 100 };
  assert.deepEqual(DI.dragDrop(d, far, row, 40, { pinned: true }), { action: "unpin" });
  assert.deepEqual(DI.dragDrop(d, far, row, 40, { pinned: false }), { action: "none" });
});

test("dropping with no drag in progress does nothing", () => {
  assert.deepEqual(DI.dragDrop(DI.initialDrag(), { x: 200, y: 530 }, row, 40, { pinned: true }), { action: "none" });
});

test("onAxis hands a column's drag to the rules along x, and leaves a row's alone", () => {
  const ghost = { x: 10, y: 200 };
  const row = { x: 4, y: 40, width: 50, height: 300 };
  assert.deepEqual(DI.onAxis(false, ghost, row), { ghost, row });
  assert.deepEqual(DI.onAxis(true, ghost, row), {
    ghost: { x: 200, y: 10 },
    row: { x: 40, y: 4, width: 300, height: 50 },
  });
  const d = DI.dragStart("pin:a", 0);
  const f = DI.onAxis(true, { x: 20, y: 40 + 2 * 50 + 10 }, { x: 4, y: 40, width: 50, height: 200 });
  assert.equal(DI.dragMove(d, f.ghost, f.row, 50, 40, 4).to, 2);
});
