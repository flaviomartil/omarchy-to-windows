// Pure Dock geometry (docs/SPEC.md "The Dock's position", "The bar"; vocabulary
// in CONTEXT.md). Where the bar and everything on it sits, for each of the four
// edges, in pixels from the top-left corner of the panel. No Quickshell or QML
// imports, so the exact same file loads as a JS import inside the shell and via
// `require` under Node for the test suite.
//
// The panel is the full area the Dock may use. `position` is the edge the Dock
// sits on: "bottom" (the default), "top", "left" or "right". On the top and
// bottom it is a row (full width); on the left and right a column (full
// height). Everything here is the same layout turned to face the edge, so the
// QML binds to these rectangles instead of choosing per edge itself.

var POSITIONS = ["top", "left", "right", "bottom"];
var DEFAULT_POSITION = "bottom";

// What the Dock's edge means, from its name. An unknown name is the default.
function edge(position) {
  var name = POSITIONS.indexOf(position) >= 0 ? position : DEFAULT_POSITION;
  var side = name === "left" || name === "right";
  return {
    position: name,
    top: name === "top",
    bottom: name === "bottom",
    left: name === "left",
    right: name === "right",
    // The Dock is a column, so its Items run along y.
    vertical: side,
  };
}

function rect(x, y, width, height) {
  return { x: x, y: y, width: width, height: height };
}

// How far an element's near side is from the Dock's edge, for `thickness` (the
// element's own size across the bar), `shown` in [0, 1] (0 hidden, 1 at rest):
// hidden parks it just beyond the edge, at rest it is centred across the bar.
function edgeGap(barThickness, thickness, shown) {
  var rest = (barThickness - thickness) / 2;
  return -thickness + (rest + thickness) * shown;
}

// Where an element of size w × h sits when it is `gap` from the Dock's edge and
// `along` the bar from its start (the left of a row, the top of a column).
function atEdge(e, panel, w, h, gap, along) {
  if (e.vertical) return rect(e.right ? panel.width - w - gap : gap, along, w, h);
  return rect(along, e.top ? gap : panel.height - h - gap, w, h);
}

// The Items shrink to fit the bar's length, so the icon size depends on the
// space the Start button and the clock take, not on where the row ends up.
// `slotExtra` is what an Item takes along the bar besides its icon.
function slotExtra(e, pad) {
  return e.vertical ? 8 : pad;
}

function reserves(e, start, clock) {
  var startReserve = start.size > 0 ? start.size + 4 : 0;
  var clockReserve = clock.visible ? (e.vertical ? clock.height + 16 : clock.width + 32) : 0;
  return { start: startReserve, clock: clockReserve };
}

// The icon size: at most `iconSize`, inside the bar (`barHeight - 20`), and
// smaller still when `count` Items would not fit the bar's length.
// opts: { position, panelWidth, panelHeight, barHeight, iconSize, pad, spacing,
//         edgePad, count, start: { size }, clock: { visible, width, height } }
function iconSize(opts) {
  var e = edge(opts.position);
  var base = Math.max(16, Math.min(opts.iconSize, opts.barHeight - 20));
  if (opts.count <= 0) return base;
  var r = reserves(e, opts.start, opts.clock);
  var extra = slotExtra(e, opts.pad);
  var length = e.vertical ? opts.panelHeight : opts.panelWidth;
  var maxLength = Math.max(0, length - opts.edgePad * 2 - 2 * (r.start + r.clock));
  var available = Math.max(0, maxLength - opts.spacing * Math.max(0, opts.count - 1));
  var natural = (base + extra) * opts.count;
  return natural <= available ? base : Math.max(16, Math.floor(available / opts.count) - extra);
}

// Where the bar and what stands on it sit.
// opts: { position, alignment ("left" | "center"), barHeight, panelWidth,
//         panelHeight, shown (0..1), autoHide, revealStripHeight, edgePad,
//         start: { size }  (the Start button's side, 0 when hidden),
//         clock: { visible, width, height },
//         row: { width, height } (the Items' own size) }
// Returns { vertical, bar, border, strip, start, clock, row }: rectangles in
// panel pixels, `border` being the bar's 1 px edge facing the screen, relative
// to the bar.
function layout(opts) {
  var e = edge(opts.position);
  var panel = { width: opts.panelWidth, height: opts.panelHeight };
  var t = opts.barHeight;
  var s = opts.shown;
  var r = reserves(e, opts.start, opts.clock);

  var barW = e.vertical ? t : panel.width;
  var barH = e.vertical ? panel.height : t;
  var barGap = (s - 1) * (e.vertical ? barW : barH);
  var bar = e.vertical
    ? rect(e.right ? panel.width - barW - barGap : barGap, 0, barW, barH)
    : rect(0, e.top ? barGap : panel.height - barH - barGap, barW, barH);

  var border = e.vertical
    ? rect(e.left ? bar.width - 1 : 0, 0, 1, bar.height)
    : rect(0, e.top ? bar.height - 1 : 0, bar.width, 1);

  var strip;
  var stripThickness = opts.autoHide ? opts.revealStripHeight : 0;
  if (e.vertical) strip = rect(e.right ? panel.width - stripThickness : 0, 0, stripThickness, panel.height);
  else strip = rect(0, e.top ? 0 : panel.height - stripThickness, panel.width, stripThickness);

  // The Start button and the Items form one group along the bar, at its start
  // or centred; the Start button leads, then the Items.
  var length = e.vertical ? panel.height : panel.width;
  var rowLength = e.vertical ? opts.row.height : opts.row.width;
  var along = opts.alignment === "left"
    ? opts.edgePad + r.start
    : (length - (r.start + rowLength)) / 2 + r.start;
  var rowThickness = e.vertical ? opts.row.width : opts.row.height;
  var row = atEdge(e, panel, opts.row.width, opts.row.height, edgeGap(t, rowThickness, s), along);

  var startSize = opts.start.size;
  var start = atEdge(e, panel, startSize, startSize, edgeGap(t, startSize, s),
    (e.vertical ? row.y : row.x) - r.start);

  // The clock is at the far end of the bar: the right of a row, the foot of a
  // column (centred across the bar either way).
  var cw = opts.clock.width;
  var ch = opts.clock.height;
  var clockThickness = e.vertical ? cw : ch;
  var clock = atEdge(e, panel, cw, ch, edgeGap(t, clockThickness, s),
    e.vertical ? panel.height - ch - 16 : panel.width - cw - 16);

  return { vertical: e.vertical, bar: bar, border: border, strip: strip, start: start, clock: clock, row: row };
}

// An Item's slot. Its running dots stand on the side of the icon away from the
// Dock's inner side: below on the bottom Dock, above on the top, and in a
// column on the outer side on the left and right. `gap` is the small space
// between icon and dots. Returns the slot's height, the icon's place in it
// (a top margin and a sideways offset from the centre) and where the dots
// stand: given the slot's width, the icon's y and height, and the dots' own
// size.
function slot(position, iconSize, gap) {
  var e = edge(position);
  return {
    height: iconSize + (e.vertical ? 8 : 3 + gap),
    iconTopMargin: e.vertical ? 4 : (e.top ? 3 + gap : 0),
    iconOffset: e.left ? 2 : (e.right ? -4 : 0),
  };
}

function dots(position, slotWidth, icon, size, gap) {
  var e = edge(position);
  if (e.vertical) {
    return {
      x: e.right ? slotWidth - size.width - gap : gap,
      y: icon.y + (icon.height - size.height) / 2,
    };
  }
  return { x: (slotWidth - size.width) / 2, y: e.top ? 0 : icon.y + icon.height + gap };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    POSITIONS: POSITIONS,
    DEFAULT_POSITION: DEFAULT_POSITION,
    edge: edge,
    iconSize: iconSize,
    layout: layout,
    slot: slot,
    dots: dots,
  };
}
