// DockPlacement.js: where popups stand, for each edge the Dock can sit on.
const test = require("node:test");
const assert = require("node:assert/strict");
const G = require("../DockGeometry.js");
const P = require("../DockPlacement.js");

const bounds = { width: 1920, height: 1054 };
const popup = { width: 200, height: 160 };
const m = 4; // margin to the panel's edges
const s = 14; // shadow
const gap = 12; // between a card and the bar
const edge = G.edge;

// The bar on each edge: a 50 px bar of a 1920 × 1054 panel.
const bars = {
  bottom: { x: 0, y: 1004, width: 1920, height: 50 },
  top: { x: 0, y: 0, width: 1920, height: 50 },
  left: { x: 0, y: 0, width: 50, height: 1054 },
  right: { x: 1870, y: 0, width: 50, height: 1054 },
};
const place = (position, along) =>
  P.beside(edge(position), P.alongBar(edge(position), along, bars[position]), popup, bounds, m, s, gap);

test("a popup keeps `gap` clear of the bar's edge, not of the Item inside the bar", () => {
  const item = { x: 500, y: 1011, width: 44, height: 35 }; // inside the bar, 7 px from its edge
  // The card's bottom edge (window bottom less the shadow) is 12 px above the bar.
  const bottom = place("bottom", item);
  assert.equal(bottom.y + popup.height - s, 1004 - gap);
  const top = place("top", { x: 500, y: 8, width: 44, height: 35 });
  assert.equal(top.y + s, 50 + gap);
  const left = place("left", { x: 3, y: 300, width: 44, height: 38 });
  assert.equal(left.x + s, 50 + gap);
  const right = place("right", { x: 1873, y: 300, width: 44, height: 38 });
  assert.equal(right.x + popup.width - s, 1870 - gap);
});

test("across the bar a popup is centred on the Item", () => {
  assert.equal(place("bottom", { x: 500, y: 1011, width: 44, height: 35 }).x, 522 - 100);
  assert.equal(place("top", { x: 500, y: 8, width: 44, height: 35 }).x, 522 - 100);
  assert.equal(place("left", { x: 3, y: 300, width: 44, height: 38 }).y, 319 - 80);
  assert.equal(place("right", { x: 1873, y: 300, width: 44, height: 38 }).y, 319 - 80);
});

test("the Preview, the Item menu and the Start menu keep the same gap from the bar", () => {
  const menu = P.startMenu({
    edge: edge("bottom"), alignment: "left", button: { x: 12, y: 1008 }, size: { width: 760, height: 640 },
    panel: bounds, barHeight: 50, margin: m, gap,
  });
  assert.equal(menu.y + 640, 1004 - gap);
  assert.equal(menu.x, 12, "the same space to the screen's edge as to the bar");
});

test("a popup is kept inside the panel by the margin, on both axes", () => {
  assert.equal(place("bottom", { x: 0, y: 1011, width: 44, height: 35 }).x, m);
  assert.equal(place("bottom", { x: 1890, y: 1011, width: 44, height: 35 }).x, 1920 - 200 - m);
  assert.equal(place("left", { x: 3, y: 10, width: 44, height: 38 }).y, m);
  assert.equal(place("left", { x: 3, y: 1040, width: 44, height: 38 }).y, 1054 - 160 - m);
});

test("the Bar menu stands beside the bar at the pointer", () => {
  const at = (position, point) => place(position, { x: point.x, y: point.y, width: 0, height: 0 });
  const point = { x: 900, y: 600 };
  assert.deepEqual(at("left", point), { x: 50 + gap - s, y: 520 });
  assert.deepEqual(at("right", point), { x: 1870 - 200 - gap + s, y: 520 });
  assert.equal(at("bottom", point).x, 800);
  assert.equal(at("bottom", point).y, 1004 - 160 - gap + s);
  assert.equal(at("top", point).y, 50 + gap - s);
});

test("a Preview slides out of the Dock's edge, away from the screen", () => {
  assert.deepEqual(P.slide(edge("bottom")), { x: 0, y: 1 });
  assert.deepEqual(P.slide(edge("top")), { x: 0, y: -1 });
  assert.deepEqual(P.slide(edge("left")), { x: -1, y: 0 });
  assert.deepEqual(P.slide(edge("right")), { x: 1, y: 0 });
});

test("the Bar menu's submenu opens on its right, or on its left for a right Dock", () => {
  assert.deepEqual(P.submenu(edge("bottom"), 239 + 28, s), { opensLeft: false, x: 267 - 28 - 1 });
  assert.deepEqual(P.submenu(edge("left"), 267, s), { opensLeft: false, x: 238 });
  assert.deepEqual(P.submenu(edge("right"), 267, s), { opensLeft: true, x: 28 });
});

function start(position, alignment, extra) {
  return P.startMenu(Object.assign({
    edge: edge(position), alignment, button: { x: 12, y: 58 }, size: { width: 760, height: 640 },
    panel: bounds, barHeight: 50, margin: m, gap,
  }, extra));
}

test("the Start menu stands above a bottom Dock and below a top one, the gap away", () => {
  assert.deepEqual(start("bottom", "left"), { x: 12, y: 1054 - 50 - 640 - gap });
  assert.deepEqual(start("top", "left"), { x: 12, y: 50 + gap });
  assert.equal(start("bottom", "center").x, (1920 - 760) / 2);
});

test("beside a side Dock the Start menu lines up with the Start button, or is centred", () => {
  assert.deepEqual(start("left", "left"), { x: 50 + gap, y: 58 });
  assert.deepEqual(start("right", "left"), { x: 1920 - 50 - 760 - gap, y: 58 });
  assert.equal(start("left", "center").y, (1054 - 640) / 2);
});

test("the Start menu stays on screen", () => {
  assert.equal(start("bottom", "left", { button: { x: -30, y: 0 } }).x, m);
  assert.equal(start("bottom", "left", { button: { x: 1900, y: 0 } }).x, 1920 - 760 - m);
  assert.equal(start("left", "left", { button: { x: 0, y: 1000 } }).y, 1054 - 640 - m);
});

test("the Start menu's room is the panel less a bar along the top or bottom and the gap to it", () => {
  assert.equal(P.startMenuRoom(edge("bottom"), 1054, 50, m, gap), 1054 - 50 - gap - m);
  assert.equal(P.startMenuRoom(edge("top"), 1054, 50, m, gap), 1054 - 50 - gap - m);
  assert.equal(P.startMenuRoom(edge("left"), 1054, 50, m, gap), 1054 - 2 * m);
});
