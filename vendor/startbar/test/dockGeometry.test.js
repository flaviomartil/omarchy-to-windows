// DockGeometry.js: where the bar and what stands on it sit, on each edge.
const test = require("node:test");
const assert = require("node:assert/strict");
const G = require("../DockGeometry.js");

// A 1920 × 1054 panel, a 50 px bar, five Items, a Start button, a clock.
function opts(position, extra) {
  const column = position === "left" || position === "right";
  return Object.assign({
    position,
    alignment: "left",
    barHeight: 50,
    panelWidth: 1920,
    panelHeight: 1054,
    shown: 1,
    autoHide: false,
    revealStripHeight: 4,
    edgePad: 12,
    start: { size: 42 },
    clock: column ? { visible: true, width: 40, height: 30 } : { visible: true, width: 60, height: 30 },
    row: column ? { width: 44, height: 300 } : { width: 300, height: 35 },
  }, extra);
}

test("edge names the four edges, and anything else is the bottom", () => {
  assert.deepEqual(G.POSITIONS, ["top", "left", "right", "bottom"]);
  assert.equal(G.edge("top").top, true);
  assert.equal(G.edge("left").vertical, true);
  assert.equal(G.edge("right").vertical, true);
  assert.equal(G.edge("bottom").vertical, false);
  assert.equal(G.edge("middle").position, "bottom");
  assert.equal(G.edge(undefined).bottom, true);
});

test("bottom: the bar fills the foot of the panel and the group sits centred in it", () => {
  const l = G.layout(opts("bottom"));
  assert.deepEqual(l.bar, { x: 0, y: 1004, width: 1920, height: 50 });
  assert.deepEqual(l.border, { x: 0, y: 0, width: 1920, height: 1 });
  // Items start after the Start button (42 + 4) and the edge padding.
  assert.deepEqual(l.row, { x: 58, y: 1011.5, width: 300, height: 35 });
  assert.deepEqual(l.start, { x: 12, y: 1008, width: 42, height: 42 });
  assert.deepEqual(l.clock, { x: 1844, y: 1014, width: 60, height: 30 });
});

test("top mirrors the bottom, with the border on the lower edge", () => {
  const l = G.layout(opts("top"));
  assert.deepEqual(l.bar, { x: 0, y: 0, width: 1920, height: 50 });
  assert.deepEqual(l.border, { x: 0, y: 49, width: 1920, height: 1 });
  assert.equal(l.row.y, 7.5);
  assert.equal(l.start.y, 4);
  assert.equal(l.clock.y, 10);
  assert.equal(l.row.x, 58);
});

test("left is a column down the left edge, the clock at its foot", () => {
  const l = G.layout(opts("left"));
  assert.equal(l.vertical, true);
  assert.deepEqual(l.bar, { x: 0, y: 0, width: 50, height: 1054 });
  assert.deepEqual(l.border, { x: 49, y: 0, width: 1, height: 1054 });
  assert.deepEqual(l.row, { x: 3, y: 58, width: 44, height: 300 });
  assert.deepEqual(l.start, { x: 4, y: 12, width: 42, height: 42 });
  assert.deepEqual(l.clock, { x: 5, y: 1008, width: 40, height: 30 });
});

test("right is the left turned to face the other way, the border on the bar's inner side", () => {
  const l = G.layout(opts("right"));
  assert.deepEqual(l.bar, { x: 1870, y: 0, width: 50, height: 1054 });
  assert.deepEqual(l.border, { x: 0, y: 0, width: 1, height: 1054 });
  assert.equal(l.row.x, 1873);
  assert.equal(l.start.x, 1874);
  assert.equal(l.clock.x, 1875);
  assert.equal(l.row.y, 58);
});

test("centred icons centre the Start button and Items together along the bar", () => {
  const row = G.layout(opts("bottom", { alignment: "center" }));
  assert.equal(row.row.x, (1920 - (46 + 300)) / 2 + 46);
  assert.equal(row.start.x, row.row.x - 46);
  const column = G.layout(opts("left", { alignment: "center" }));
  assert.equal(column.row.y, (1054 - (46 + 300)) / 2 + 46);
  assert.equal(column.start.y, column.row.y - 46);
});

test("hidden parks every element just beyond the edge, and shown 0.5 is halfway", () => {
  const bottom = G.layout(opts("bottom", { shown: 0 }));
  assert.equal(bottom.bar.y, 1054);
  assert.equal(bottom.row.y, 1054);
  assert.equal(bottom.start.y, 1054);
  assert.equal(bottom.clock.y, 1054);
  const top = G.layout(opts("top", { shown: 0 }));
  assert.equal(top.bar.y, -50);
  assert.equal(top.row.y + top.row.height, 0);
  const left = G.layout(opts("left", { shown: 0 }));
  assert.equal(left.bar.x, -50);
  assert.equal(left.row.x + left.row.width, 0);
  const right = G.layout(opts("right", { shown: 0 }));
  assert.equal(right.bar.x, 1920);
  assert.equal(right.row.x, 1920);
  const half = G.layout(opts("bottom", { shown: 0.5 }));
  assert.equal(half.bar.y, (1004 + 1054) / 2);
});

test("the Reveal Strip is a band along the Dock's edge, only with auto-hide", () => {
  assert.equal(G.layout(opts("bottom")).strip.height, 0);
  assert.deepEqual(G.layout(opts("bottom", { autoHide: true })).strip, { x: 0, y: 1050, width: 1920, height: 4 });
  assert.deepEqual(G.layout(opts("top", { autoHide: true })).strip, { x: 0, y: 0, width: 1920, height: 4 });
  assert.deepEqual(G.layout(opts("left", { autoHide: true })).strip, { x: 0, y: 0, width: 4, height: 1054 });
  assert.deepEqual(G.layout(opts("right", { autoHide: true })).strip, { x: 1916, y: 0, width: 4, height: 1054 });
});

test("an absent Start button takes no room and a hidden clock none either", () => {
  const l = G.layout(opts("bottom", { start: { size: 0 }, clock: { visible: false, width: 0, height: 0 } }));
  assert.equal(l.row.x, 12);
  assert.equal(l.start.width, 0);
});

test("every element stays inside the bar's thickness when shown, on every edge", () => {
  for (const position of G.POSITIONS) {
    const l = G.layout(opts(position));
    const e = G.edge(position);
    const across = (r) => (e.vertical ? [r.x - l.bar.x, r.x - l.bar.x + r.width] : [r.y - l.bar.y, r.y - l.bar.y + r.height]);
    for (const name of ["row", "start", "clock"]) {
      const [near, far] = across(l[name]);
      assert.ok(near >= 0 && far <= 50, `${position} ${name} ${near}..${far}`);
    }
  }
});

function fit(position, count, extra) {
  const column = position === "left" || position === "right";
  return G.iconSize(Object.assign({
    position, panelWidth: 1920, panelHeight: 1054, barHeight: 50, iconSize: 48, pad: 16, spacing: 2,
    edgePad: 12, count, start: { size: 42 }, clock: { visible: false, width: 0, height: 0 },
  }, extra));
}

test("icons are iconSize at most and fit inside the bar", () => {
  assert.equal(fit("bottom", 5), 30);
  assert.equal(fit("bottom", 5, { iconSize: 20 }), 20);
  assert.equal(fit("bottom", 5, { barHeight: 24 }), 16);
  assert.equal(fit("bottom", 0), 30);
});

test("icons shrink to fit the bar's length, a column's being the panel's height", () => {
  assert.equal(fit("bottom", 40), 27);
  assert.ok(fit("left", 40) < 30, "a 1054 px column cannot hold 40 icons at full size");
  assert.equal(fit("left", 10), 30);
  assert.ok(fit("bottom", 200) >= 16);
});

test("the clock's room is taken off the bar's length, along the other axis for a column", () => {
  const wide = fit("bottom", 40, { clock: { visible: true, width: 80, height: 30 } });
  assert.ok(wide <= fit("bottom", 40));
  const tall = fit("left", 20, { clock: { visible: true, width: 40, height: 30 } });
  assert.ok(tall <= fit("left", 20));
});

test("an Item's slot: dots below, above, or beside the icon", () => {
  assert.deepEqual(G.slot("bottom", 30, 2), { height: 35, iconTopMargin: 0, iconOffset: 0 });
  assert.deepEqual(G.slot("top", 30, 2), { height: 35, iconTopMargin: 5, iconOffset: 0 });
  assert.deepEqual(G.slot("left", 30, 2), { height: 38, iconTopMargin: 4, iconOffset: 2 });
  assert.deepEqual(G.slot("right", 30, 2), { height: 38, iconTopMargin: 4, iconOffset: -4 });
});

test("where the dots stand in a slot, for a row of three and a column of one", () => {
  const icon = { y: 0, height: 30 };
  assert.deepEqual(G.dots("bottom", 46, icon, { width: 18, height: 3 }, 2), { x: 14, y: 32 });
  assert.deepEqual(G.dots("top", 46, { y: 5, height: 30 }, { width: 18, height: 3 }, 2), { x: 14, y: 0 });
  assert.deepEqual(G.dots("left", 46, { y: 4, height: 30 }, { width: 3, height: 6 }, 2), { x: 2, y: 16 });
  assert.deepEqual(G.dots("right", 46, { y: 4, height: 30 }, { width: 3, height: 6 }, 2), { x: 41, y: 16 });
});
