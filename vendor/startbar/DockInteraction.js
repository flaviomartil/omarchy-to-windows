// Pure Dock interaction state (docs/SPEC.md "Reveal", "Input"; vocabulary in
// CONTEXT.md). No Quickshell or QML imports, so the exact same file loads as
// a JS import inside the shell and via `require` under Node for the test
// suite.
//
// Two small state machines that used to be smeared across QObjects, Timers
// and popup handlers in Service.qml: whether the Dock is Revealed, and what a
// drag decides. Each takes an event and returns the next state; Service.qml
// keeps the state, arms the timers the result names and paints. The hover
// Preview, Peek and the Preview menu are in DockPreview.js.
//
// A transition returns `{ state, timers }`. `timers` maps a timer name to
// "start" (restart it) or "stop"; a timer not named is left alone.

// --- Reveal -----------------------------------------------------------------
//
// Revealed once any of the flags below has held for the reveal delay, and
// Hidden again once none has for the hide delay. `menu` holds the Dock up for
// a whole Item or Preview menu visit, `barMenu` for the Bar menu's, `startMenu`
// for the Start menu's and `drag` for a whole drag, independent of hover,
// since the pointer leaves both the strip and the Dock then. Each holder has
// its own flag, so one closing never drops another's hold.

var REVEAL_FLAGS = ["strip", "dock", "bar", "start", "preview", "menu", "barMenu", "startMenu", "drag"];

function initialReveal() {
  var flags = {};
  for (var i = 0; i < REVEAL_FLAGS.length; i++) flags[REVEAL_FLAGS[i]] = false;
  return { flags: flags, revealed: false };
}

function isHeld(state) {
  for (var i = 0; i < REVEAL_FLAGS.length; i++) {
    if (state.flags[REVEAL_FLAGS[i]]) return true;
  }
  return false;
}

// A flag changed. Timers only move when "any flag held" itself flips.
function setRevealFlag(state, name, value) {
  if (REVEAL_FLAGS.indexOf(name) < 0) return { state: state, timers: {} };
  var flags = {};
  for (var i = 0; i < REVEAL_FLAGS.length; i++) flags[REVEAL_FLAGS[i]] = state.flags[REVEAL_FLAGS[i]];
  var before = isHeld(state);
  flags[name] = !!value;
  var next = { flags: flags, revealed: state.revealed };
  var after = isHeld(next);
  if (after === before) return { state: next, timers: {} };
  if (after) return { state: next, timers: state.revealed ? { hide: "stop" } : { hide: "stop", reveal: "start" } };
  return { state: next, timers: { reveal: "stop", hide: "start" } };
}

function revealTimerFired(state) {
  return { state: { flags: state.flags, revealed: true }, timers: {} };
}

function hideTimerFired(state) {
  return { state: { flags: state.flags, revealed: false }, timers: {} };
}

// --- Drag -------------------------------------------------------------------
//
// A drag moves a ghost of the Item. The Items between its own slot and the
// slot under the ghost step aside to show where it would land (`slotShift`),
// and the ghost stops at the first and last slot however far the pointer goes
// on (`clampGhostX`). Sideways there is no drag-out: only leaving the bar
// vertically, by half an icon, makes the drop a drag-out: unpin if the Item
// is pinned, else a snap-back with nothing to persist.

function initialDrag() {
  return { key: "", from: -1, to: -1, outside: false };
}

function dragActive(drag) {
  return drag.key !== "";
}

// `startIndex` is the dragged Item's current slot; the drag begins with its
// target on that slot, i.e. "no move".
function dragStart(key, startIndex) {
  return { key: key, from: startIndex, to: startIndex, outside: false };
}

// The ghost moved. `ghost` is its centre { x, y }; `row` the Dock row's
// rectangle { x, y, width, height }; `step` the distance between Item slots
// (item width plus spacing); `count` how many Items are on the Dock. `to` is
// the slot under the ghost, 0..count-1, which is also the index the Item
// lands on when dropped.
function dragMove(drag, ghost, row, step, iconSize, count) {
  if (!dragActive(drag)) return drag;
  var slot = step > 0 ? Math.floor((ghost.x - row.x) / step) : 0;
  return {
    key: drag.key,
    from: drag.from,
    to: Math.max(0, Math.min(slot, count - 1)),
    outside: isOutsideRow(ghost, row, iconSize),
  };
}

// Where the ghost's left edge is drawn for a pointer-driven `x`: it never
// goes beyond the first or last slot.
function clampGhostX(x, row, step, count) {
  var last = row.x + Math.max(0, count - 1) * step;
  return Math.max(row.x, Math.min(x, last));
}

// How far the Item in slot `index` is drawn from its own slot while a drag is
// on: one step toward the dragged Item's vacated slot, for each Item the
// dragged Item has passed. The dragged Item's own slot stays where it is.
function slotShift(drag, index, step) {
  if (!dragActive(drag) || index === drag.from) return 0;
  if (drag.from < drag.to && index > drag.from && index <= drag.to) return -step;
  if (drag.to < drag.from && index >= drag.to && index < drag.from) return step;
  return 0;
}

// The drag rules above work along x and across y. A column of Items runs the
// other way, so for it they are given the ghost and row with x and y swapped.
function onAxis(vertical, ghost, row) {
  if (!vertical) return { ghost: ghost, row: row };
  return {
    ghost: { x: ghost.y, y: ghost.x },
    row: { x: row.y, y: row.x, width: row.height, height: row.width },
  };
}

function isOutsideRow(ghost, row, iconSize) {
  var margin = iconSize / 2;
  return ghost.y < row.y - margin || ghost.y > row.y + row.height + margin;
}

// The slot the Item ends up in when dropped now.
function finalIndex(drag) {
  return drag.to;
}

// What dropping does. `item` is { pinned } (a pin Item counts as pinned).
// Recomputes "outside" from the ghost's final position rather than trusting
// the last move. Returns { action: "reorder", index } | { action: "unpin" }
// | { action: "none" }; the caller clears the drag state first.
function dragDrop(drag, ghost, row, iconSize, item) {
  if (!dragActive(drag)) return { action: "none" };
  if (isOutsideRow(ghost, row, iconSize)) {
    return item && item.pinned ? { action: "unpin" } : { action: "none" };
  }
  if (drag.to >= 0) return { action: "reorder", index: finalIndex(drag) };
  return { action: "none" };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    REVEAL_FLAGS: REVEAL_FLAGS,
    initialReveal: initialReveal,
    isHeld: isHeld,
    setRevealFlag: setRevealFlag,
    revealTimerFired: revealTimerFired,
    hideTimerFired: hideTimerFired,
    initialDrag: initialDrag,
    dragActive: dragActive,
    dragStart: dragStart,
    dragMove: dragMove,
    onAxis: onAxis,
    isOutsideRow: isOutsideRow,
    clampGhostX: clampGhostX,
    slotShift: slotShift,
    finalIndex: finalIndex,
    dragDrop: dragDrop,
  };
}
