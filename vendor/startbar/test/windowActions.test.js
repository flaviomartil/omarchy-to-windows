const test = require("node:test");
const assert = require("node:assert/strict");
const { windowActions } = require("../DockModel.js");

const ids = (list) => list.map((a) => a.id);
const label = (list, id) => list.find((a) => a.id === id).label;

test("a tiled window offers maximize, full screen, float and scratchpad", () => {
  const actions = windowActions({ fullscreen: 0, floating: false, pinned: false, workspace: "1" });
  assert.deepEqual(ids(actions), ["maximize", "fullscreen", "float", "scratchpad"]);
  assert.equal(label(actions, "maximize"), "Maximize");
  assert.equal(label(actions, "fullscreen"), "Full screen");
  assert.equal(label(actions, "float"), "Float");
});

test("labels flip to their undo while the state is active", () => {
  const maxed = windowActions({ fullscreen: 1, floating: false, workspace: "1" });
  assert.equal(label(maxed, "maximize"), "Restore");
  assert.equal(label(maxed, "fullscreen"), "Full screen");

  const full = windowActions({ fullscreen: 2, floating: false, workspace: "1" });
  assert.equal(label(full, "fullscreen"), "Exit full screen");
  assert.equal(label(full, "maximize"), "Maximize");
});

test("a floating window also offers Center and Pin on top; Tile replaces Float", () => {
  const actions = windowActions({ fullscreen: 0, floating: true, pinned: false, workspace: "2" });
  assert.deepEqual(ids(actions), ["maximize", "fullscreen", "float", "center", "pin", "scratchpad"]);
  assert.equal(label(actions, "float"), "Tile");
  assert.equal(label(actions, "pin"), "Pin on top");
  assert.equal(label(windowActions({ floating: true, pinned: true, workspace: "2" }), "pin"), "Unpin from top");
});

test("a window already in the scratchpad can't be moved there again", () => {
  const actions = windowActions({ floating: false, workspace: "special:scratchpad" });
  assert.equal(ids(actions).includes("scratchpad"), false);
});

test("missing fields are treated as off", () => {
  assert.deepEqual(ids(windowActions({})), ["maximize", "fullscreen", "float", "scratchpad"]);
  assert.deepEqual(windowActions(null), []);
});
