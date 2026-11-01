// Pure popup placement (docs/SPEC.md "The Dock's position", "Input"; vocabulary
// in CONTEXT.md). Where a Preview, the Item menu, the Bar menu, its submenu and
// the Start menu go, for each edge the Dock can sit on. Positions are pixels in
// the panel's own coordinates, the same space the rectangles of DockGeometry.js
// are in. No Quickshell or QML imports, so the exact same file loads as a JS
// import inside the shell and via `require` under Node for the test suite.
//
// Each function takes the Dock's edge as DockGeometry.edge() describes it
// ({ vertical, top, left, right, ... }), so the two modules agree on what an
// edge is without importing each other.
//
// A popup is a window with a drop shadow's room (`shadow`) all round its card, so
// it is sized and placed as the window; what the card does is up to the caller.
// `gap` is the space between a popup's card and the bar it rises from (the same
// as the space the Start menu keeps at its side, as on Windows 11), and `margin`
// the least space kept to the panel's own edges.

function clamp(value, low, high) {
  return Math.max(low, Math.min(value, high));
}

// Where a popup of `popup` { width, height } stands beside `target` { x, y,
// width, height }, on the side of it that faces into the screen: above a bottom
// Dock's bar, below a top Dock's, to the right of a left Dock's and to the left
// of a right Dock's, `gap` away from it. Across that, it is centred on the
// target, and kept inside `bounds` { width, height } by `margin`. Returns the
// window's { x, y }.
function beside(e, target, popup, bounds, margin, shadow, gap) {
  var x;
  var y;
  if (e.vertical) {
    x = e.right ? target.x - popup.width - gap + shadow : target.x + target.width + gap - shadow;
    y = target.y + target.height / 2 - popup.height / 2;
  } else {
    x = target.x + target.width / 2 - popup.width / 2;
    y = e.top ? target.y + target.height + gap - shadow : target.y - popup.height - gap + shadow;
  }
  return {
    x: clamp(x, margin, bounds.width - popup.width - margin),
    y: clamp(y, margin, bounds.height - popup.height - margin),
  };
}

// What a popup stands beside: the bar, at `along` { x, y, width, height }, the
// Item (or the pointer, with no size) it belongs to. Along the bar the popup
// follows `along`; across it, it keeps clear of the bar's own edge, not the
// Item's, which stands inside the bar with room around it. `bar` is the bar's
// rectangle (DockGeometry.layout's `bar`).
function alongBar(e, along, bar) {
  if (e.vertical) return { x: bar.x, y: along.y, width: bar.width, height: along.height };
  return { x: along.x, y: bar.y, width: along.width, height: bar.height };
}

// Which way a Preview slides out of the Dock's edge: the unit step it starts
// from, away from the screen's centre.
function slide(e) {
  if (e.vertical) return { x: e.left ? -1 : 1, y: 0 };
  return { x: 0, y: e.top ? -1 : 1 };
}

// The Bar menu's submenu stands against its parent menu, on the parent's right
// or, for a right Dock, on its left (where the screen has room); the section
// chevrons point the same way. `x` is the anchor's x in the parent window,
// frame to frame.
function submenu(e, parentWidth, shadow) {
  var opensLeft = e.right;
  return { opensLeft: opensLeft, x: opensLeft ? shadow * 2 : parentWidth - shadow * 2 - 1 };
}

// The room the Start menu may take in height: the panel less a bar along the
// bottom or top and the gap to it, and the margins.
function startMenuRoom(e, panelHeight, barHeight, margin, gap) {
  return e.vertical ? panelHeight - margin * 2 : panelHeight - barHeight - gap - margin;
}

// Where the Start menu's card goes. opts: { edge, alignment, button { x, y }
// (the Start button), size { width, height }, panel { width, height },
// barHeight, margin, gap }. It stands above a bottom Dock, below a top one, beside a
// side Dock; across that its start lines up with the Start button (left-aligned
// icons) or it is centred on the screen. It stays on screen.
function startMenu(opts) {
  var e = opts.edge;
  var size = opts.size;
  var panel = opts.panel;
  var margin = opts.margin;
  var left = opts.alignment === "left";
  var x;
  var y;
  if (e.vertical) {
    x = e.right ? panel.width - opts.barHeight - size.width - opts.gap : opts.barHeight + opts.gap;
    y = clamp(left ? opts.button.y : (panel.height - size.height) / 2, margin, panel.height - size.height - margin);
  } else {
    x = clamp(left ? opts.button.x : (panel.width - size.width) / 2, margin, panel.width - size.width - margin);
    y = e.top ? opts.barHeight + opts.gap : Math.max(margin, panel.height - opts.barHeight - size.height - opts.gap);
  }
  return { x: Math.round(x), y: Math.round(y) };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    beside: beside,
    alongBar: alongBar,
    slide: slide,
    submenu: submenu,
    startMenuRoom: startMenuRoom,
    startMenu: startMenu,
  };
}
