const test = require("node:test");
const assert = require("node:assert/strict");
const {
  effectiveView,
  schemeColors,
  resolveStartIcon,
} = require("../DockConfig.js");

const effectiveTaskbar = (entry) => effectiveView(entry).taskbar;

test("a leftover style key, either value or nonsense, changes nothing", () => {
  const plain = effectiveView({ alignment: "left", pins: ["a"] });
  for (const style of ["dock", "taskbar", "nonsense", 3, null]) {
    assert.deepEqual(effectiveView({ alignment: "left", pins: ["a"], style }), plain, String(style));
  }
  assert.deepEqual(effectiveView({ style: "dock" }), effectiveView({}));
  assert.deepEqual(effectiveView({ style: "dock" }), effectiveView(null));
  assert.equal("style" in effectiveView({ style: "dock" }).taskbar, false);
  assert.equal("style" in effectiveView({ style: "dock" }).values, false);
});

test("a leftover style: dock does not force auto-hide on", () => {
  assert.equal(effectiveTaskbar({ style: "dock" }).autoHide, false);
  assert.equal(effectiveTaskbar({ style: "dock", autoHide: true }).autoHide, true);
});

test("bar defaults: always visible, left-aligned, theme colours, built-in Start menu, no clock, grouped windows, no hover-open", () => {
  assert.deepEqual(effectiveTaskbar({}), {
    alignment: "left",
    position: "bottom",
    reserveSpace: false,
    edgeSpacing: 12,
    colorScheme: "theme",
    autoHide: false,
    barHeight: 48,
    opacity: 0.9,
    transparent: false,
    showStart: true,
    startCommand: "builtin",
    startIcon: "grid",
    showClock: false,
    showPreviews: true,
    previewWarpPointer: true,
    previewPeek: true,
    previewSlide: true,
    showWorkspaceBadge: false,
    groupWindows: true,
    startHoverOpen: false,
    hideOmarchyDock: true,
    newWindowWorkspace: "off",
  });
});

test("the bar honours valid values and autoHide", () => {
  const s = effectiveTaskbar({
    alignment: "left",
    colorScheme: "dark",
    autoHide: true,
    barHeight: 40,
    opacity: 0.5,
    transparent: true,
    showStart: false,
    startCommand: "walker",
    startIcon: "omarchy",
    showClock: false,
    showPreviews: false,
  });
  assert.equal(s.alignment, "left");
  assert.equal(s.colorScheme, "dark");
  assert.equal(s.autoHide, true);
  assert.equal(s.barHeight, 40);
  assert.equal(s.opacity, 0.5);
  assert.equal(s.transparent, true);
  assert.equal(s.showStart, false);
  assert.equal(s.startCommand, "walker");
  assert.equal(s.startIcon, "omarchy");
  assert.equal(s.showClock, false);
  assert.equal(s.showPreviews, false);
  assert.equal(effectiveTaskbar({ startHoverOpen: true }).startHoverOpen, true);
  assert.equal(effectiveTaskbar({ startHoverOpen: 1 }).startHoverOpen, false);
  assert.equal(effectiveTaskbar({ groupWindows: false }).groupWindows, false);
  assert.equal(effectiveTaskbar({ groupWindows: "no" }).groupWindows, true);
  assert.equal(effectiveTaskbar({ alignment: "center" }).alignment, "center");
  assert.equal(effectiveTaskbar({ showWorkspaceBadge: true }).showWorkspaceBadge, true);
  assert.equal(effectiveTaskbar({ showWorkspaceBadge: true }).showWorkspaceBadge, true);
  assert.equal(effectiveTaskbar({ showWorkspaceBadge: "yes" }).showWorkspaceBadge, false);
  assert.equal(effectiveTaskbar({ previewWarpPointer: false }).previewWarpPointer, false);
  assert.equal(effectiveTaskbar({ previewWarpPointer: "no" }).previewWarpPointer, true);
});

test("unusable taskbar values fall back to defaults; opacity is clamped to 0..1", () => {
  const s = effectiveTaskbar({
    alignment: "right",
    colorScheme: "blue",
    barHeight: -3,
    opacity: 7,
    startCommand: "   ",
    startIcon: 5,
    showStart: "yes",
  });
  assert.equal(s.alignment, "left");
  assert.equal(s.colorScheme, "theme");
  assert.equal(s.barHeight, 48);
  assert.equal(s.opacity, 1);
  assert.equal(s.startCommand, "builtin");
  assert.equal(s.startIcon, "grid");
  assert.equal(s.showStart, true);
  assert.equal(effectiveTaskbar({ opacity: 0 }).opacity, 0);
  assert.equal(effectiveTaskbar({ opacity: -1 }).opacity, 0);
});

test("schemeColors is null for the theme and a full palette for dark and light", () => {
  assert.equal(schemeColors("theme"), null);
  const keys = ["background", "foreground", "muted", "accent", "border"];
  for (const scheme of ["dark", "light"]) {
    const palette = schemeColors(scheme);
    for (const key of keys) assert.match(palette[key], /^#[0-9a-f]{6}$/i);
  }
  assert.notEqual(schemeColors("dark").background, schemeColors("light").background);
});

test("resolveStartIcon: grid, an absolute image path, or an icon-theme name", () => {
  assert.deepEqual(resolveStartIcon("grid"), { kind: "grid" });
  assert.deepEqual(resolveStartIcon("/home/u/logo.png"), { kind: "path", value: "/home/u/logo.png" });
  assert.deepEqual(resolveStartIcon("omarchy"), { kind: "icon", value: "omarchy" });
  assert.deepEqual(resolveStartIcon("arch"), { kind: "icon", value: "archlinux" });
  assert.deepEqual(resolveStartIcon("linux"), { kind: "icon", value: "tux" });
  assert.deepEqual(resolveStartIcon("folder"), { kind: "icon", value: "folder" });
  assert.deepEqual(resolveStartIcon(""), { kind: "grid" });
});

const { barMenuRows, barMenuLabels, barSubmenuLabels } = require("../DockConfig.js");

// Every row, sections' children included.
const everyRow = (rows) => rows.flatMap((r) => [r, ...(r.children || [])]);

test("barMenuRows checks the current choice inside each section", () => {
  const rows = barMenuRows(effectiveTaskbar({ alignment: "left", colorScheme: "dark" }));
  const section = (label) => rows.find((r) => r.label === label);

  const colors = Object.fromEntries(section("Colors").children.map((r) => [r.label, r.checked]));
  assert.deepEqual(colors, { Theme: false, Dark: true, Light: false });
  const align = Object.fromEntries(section("Icon alignment").children.map((r) => [r.label, r.checked]));
  assert.deepEqual(align, { Left: true, Center: false });
  assert.equal(rows.find((r) => r.label === "Auto-hide").checked, false);
});

test("each row's patch sets its own key; toggles flip the current value", () => {
  const rows = everyRow(barMenuRows(effectiveTaskbar({ showClock: true, autoHide: false })));
  const patch = (label) => rows.find((r) => r.label === label).patch;

  assert.deepEqual(patch("Center"), { alignment: "center" });
  assert.deepEqual(patch("Light"), { colorScheme: "light" });
  assert.deepEqual(patch("Auto-hide"), { autoHide: true });
  assert.deepEqual(patch("Clock"), { showClock: false });
  assert.deepEqual(patch("Show previews"), { showPreviews: false });
  assert.deepEqual(patch("Pointer follows click"), { previewWarpPointer: false });
  assert.deepEqual(patch("Show window on hover"), { previewPeek: false });
  assert.deepEqual(patch("Workspace badge"), { showWorkspaceBadge: true });
  assert.deepEqual(patch("Group windows of one app"), { groupWindows: false });
  assert.deepEqual(patch("Open on hover"), { startHoverOpen: true });
  assert.deepEqual(patch("Transparent background"), { transparent: true });
  assert.deepEqual(patch("Show Start button"), { showStart: false });
  assert.equal(rows.some((r) => /style/i.test(r.label)), false);
});

test("the top level is short: sections and the everyday toggles, then Settings", () => {
  const rows = barMenuRows(effectiveTaskbar({}));
  assert.ok(rows.length <= 11, `${rows.length} top-level rows`);
  assert.deepEqual(rows.filter((r) => r.children).map((r) => r.label), ["Icon alignment", "Position", "Colors", "Start button", "Window previews"]);
  assert.equal(rows.some((r) => /Omarchy's dock/.test(r.label)), false);
});

test("groups are marked so the menu can draw a divider before each new one", () => {
  const rows = barMenuRows(effectiveTaskbar({}));
  const groups = rows.map((r) => r.group);
  assert.deepEqual(groups, [...groups].sort((a, b) => a - b));
  assert.ok(new Set(groups).size >= 3);
  assert.notEqual(rows.find((r) => r.label === "Auto-hide").group, rows.find((r) => r.label === "Settings\u2026").group);
});

test("the menu can switch the Start button between the built-in menu and the Omarchy menu", () => {
  const start = (entry) => barMenuRows(effectiveTaskbar(entry)).find((r) => r.label === "Start button");
  const omarchy = start({ startCommand: "omarchy-menu toggle apps" });
  const kid = (section, label) => section.children.find((r) => r.label === label);
  assert.equal(kid(omarchy, "Open the built-in menu").checked, false);
  assert.equal(kid(omarchy, "Open the Omarchy menu").checked, true);
  assert.deepEqual(kid(omarchy, "Open the built-in menu").patch, { startCommand: "builtin" });

  const builtin = start({});
  assert.equal(kid(builtin, "Open the built-in menu").checked, true);
  assert.deepEqual(kid(builtin, "Open the Omarchy menu").patch, { startCommand: "omarchy-menu toggle apps" });
});

test("a row that depends on another setting is disabled while that one is off", () => {
  const kids = (entry, label) => barMenuRows(effectiveTaskbar(entry)).find((r) => r.label === label).children;
  const enabled = (list) => Object.fromEntries(list.map((r) => [r.label, r.enabled]));

  assert.deepEqual(enabled(kids({ showPreviews: false }, "Window previews")), {
    "Show previews": true, "Show window on hover": false, "Pointer follows click": false,
  });
  assert.equal(enabled(kids({}, "Window previews"))["Show window on hover"], true);
  const start = enabled(kids({ showStart: false }, "Start button"));
  assert.deepEqual(Object.values(start), [true, false, false, false]);
  assert.equal(enabled(kids({ startCommand: "omarchy-menu toggle apps" }, "Start button"))["Open on hover"], false);
  assert.equal(enabled(kids({}, "Start button"))["Open on hover"], true);
});

test("barMenuLabels sizes the menu, barSubmenuLabels its submenus", () => {
  const rows = barMenuRows(effectiveTaskbar({}));
  const top = barMenuLabels(rows);
  assert.ok(top.includes("Colors"));
  assert.ok(top.includes("Settings\u2026"));
  assert.equal(top.includes("Open the built-in menu"), false);
  const sub = barSubmenuLabels(rows);
  assert.ok(sub.includes("Open the built-in menu"));
  assert.equal(sub.includes("Colors"), false);
});

const { longestLabel } = require("../DockConfig.js");

test("longestLabel picks the longest label from rows or strings, for sizing a menu", () => {
  assert.equal(longestLabel([{ label: "Clock" }, { label: "Pointer follows preview click" }, { label: "Auto-hide" }]), "Pointer follows preview click");
  assert.equal(longestLabel(["a", "abc", "ab"]), "abc");
  assert.equal(longestLabel([]), "");
  assert.equal(longestLabel(null), "");
  assert.equal(longestLabel([{ label: "x" }, {}, null]), "x");
});

test("position is bottom unless the config says top", () => {
  assert.equal(effectiveTaskbar({}).position, "bottom");
  assert.equal(effectiveTaskbar({ position: "top" }).position, "top");
  assert.equal(effectiveTaskbar({ position: "left" }).position, "left");
  assert.equal(effectiveTaskbar({ position: "right" }).position, "right");
  assert.equal(effectiveTaskbar({ position: "middle" }).position, "bottom");
});

test("edgeSpacing is 12, may be zero, and a bad value falls back", () => {
  assert.equal(effectiveTaskbar({}).edgeSpacing, 12);
  assert.equal(effectiveTaskbar({ edgeSpacing: 0 }).edgeSpacing, 0);
  assert.equal(effectiveTaskbar({ edgeSpacing: 20 }).edgeSpacing, 20);
  assert.equal(effectiveTaskbar({ edgeSpacing: -3 }).edgeSpacing, 12);
  assert.equal(effectiveTaskbar({ edgeSpacing: "wide" }).edgeSpacing, 12);
});
