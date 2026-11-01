const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { buildDockItems, menuFor } = require("../DockModel.js");
const { effectiveView, applyIntent } = require("../DockConfig.js");

function makeWindow(overrides) {
  return Object.assign(
    { id: "win", class: "App", workspace: "1", openedAt: 0 },
    overrides,
  );
}

function resolverFor(appsByClass) {
  return function resolveApp(window) {
    return appsByClass[window.class] || null;
  };
}

function itemIds(items) {
  return items.map((item) => item.window.id);
}

const resolveBrowserAndTerminal = resolverFor({
  firefox: { id: "firefox" },
  alacritty: { id: "alacritty" },
});

test("DockModel has no Quickshell or QML imports, so Node can load it directly", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "DockModel.js"),
    "utf8",
  );
  assert.doesNotMatch(source, /^\s*import\s/m);
  assert.equal(typeof buildDockItems, "function");
});

test("Window Items come out in Launch Order", () => {
  const resolveApp = resolveBrowserAndTerminal;
  const windows = [
    makeWindow({ id: "w1", class: "firefox", openedAt: 2 }),
    makeWindow({ id: "w2", class: "alacritty", openedAt: 1 }),
  ];

  const items = buildDockItems(windows, resolveApp);

  assert.deepEqual(itemIds(items), ["w2", "w1"]);
});

test("a new Window joins the Window Items of its own App rather than the end of Launch Order", () => {
  const resolveApp = resolveBrowserAndTerminal;
  const windows = [
    makeWindow({ id: "firefox-1", class: "firefox", openedAt: 1 }),
    makeWindow({ id: "alacritty-1", class: "alacritty", openedAt: 2 }),
    makeWindow({ id: "firefox-2", class: "firefox", openedAt: 3 }),
  ];

  const items = buildDockItems(windows, resolveApp);

  assert.deepEqual(itemIds(items), ["firefox-1", "firefox-2", "alacritty-1"]);
});

test("Launch Order is recomputed from the current Windows, so closing one doesn't strand its App's other Windows", () => {
  const resolveApp = resolveBrowserAndTerminal;
  const windows = [
    makeWindow({ id: "alacritty-1", class: "alacritty", openedAt: 2 }),
    makeWindow({ id: "firefox-2", class: "firefox", openedAt: 3 }),
  ];

  const items = buildDockItems(windows, resolveApp);

  assert.deepEqual(itemIds(items), ["alacritty-1", "firefox-2"]);
});

test("a Window whose App the resolver cannot identify yields a Letter Tile Item showing the first letter of its class", () => {
  const windows = [makeWindow({ id: "w1", class: "Unknown-Editor", openedAt: 1 })];

  const items = buildDockItems(windows, () => undefined);

  assert.equal(items[0].app, null);
  assert.equal(items[0].letter, "U");
});

test("a new Window whose App can't be resolved joins the Letter Tile Items of its own class rather than the end of Launch Order", () => {
  const windows = [
    makeWindow({ id: "unknown-1", class: "Unknown-Editor", openedAt: 1 }),
    makeWindow({ id: "firefox-1", class: "firefox", openedAt: 2 }),
    makeWindow({ id: "unknown-2", class: "Unknown-Editor", openedAt: 3 }),
  ];

  const items = buildDockItems(windows, resolverFor({ firefox: { id: "firefox" } }));

  assert.deepEqual(itemIds(items), ["unknown-1", "unknown-2", "firefox-1"]);
});

test("Windows resolved to an App carry no Letter Tile", () => {
  const windows = [makeWindow({ id: "w1", class: "firefox", openedAt: 1 })];

  const items = buildDockItems(windows, resolverFor({ firefox: { id: "firefox" } }));

  assert.equal(items[0].app.id, "firefox");
  assert.equal(items[0].letter, null);
});

test("Windows on a special workspace are included among the Window Items", () => {
  const windows = [
    makeWindow({ id: "w1", class: "firefox", workspace: "1", openedAt: 1 }),
    makeWindow({
      id: "w2",
      class: "btop",
      workspace: "special:scratchpad",
      openedAt: 2,
    }),
  ];

  const items = buildDockItems(windows, () => null);

  assert.deepEqual(itemIds(items), ["w1", "w2"]);
});

test("the Active Window's Item carries the Active flag, every other Item does not", () => {
  const windows = [
    makeWindow({ id: "w1", openedAt: 1, active: true }),
    makeWindow({ id: "w2", openedAt: 2 }),
  ];

  const items = buildDockItems(windows, () => null);

  assert.equal(items[0].active, true);
  assert.equal(items[1].active, false);
});

test("a Window requesting Attention has its Item carry the Attention flag", () => {
  const windows = [
    makeWindow({ id: "w1", openedAt: 1, attention: true }),
    makeWindow({ id: "w2", openedAt: 2 }),
  ];

  const items = buildDockItems(windows, () => null);

  assert.equal(items[0].attention, true);
  assert.equal(items[1].attention, false);
});

test("a Window Item's workspace badge is the workspace name for a regular workspace", () => {
  const windows = [makeWindow({ id: "w1", workspace: "3", openedAt: 1 })];

  const items = buildDockItems(windows, () => null);

  assert.equal(items[0].badge, "3");
});

test("a Window Item's workspace badge is the special workspace's own name, without Hyprland's \"special:\" prefix", () => {
  const windows = [
    makeWindow({ id: "w1", workspace: "special:scratchpad", openedAt: 1 }),
  ];

  const items = buildDockItems(windows, () => null);

  assert.equal(items[0].badge, "scratchpad");
});

function describeItem(item) {
  return item.kind === "pin" ? `pin:${item.appId}` : `window:${item.window.id}`;
}

function describeItems(items) {
  return items.map(describeItem);
}

test("a Window Item resolved to an App is reported as pinnable", () => {
  const windows = [makeWindow({ id: "w1", class: "firefox" })];

  const items = buildDockItems(windows, resolveBrowserAndTerminal);

  assert.equal(items[0].pinnable, true);
});

test("a Letter Tile Window Item is reported as not pinnable", () => {
  const windows = [makeWindow({ id: "w1", class: "Unknown-Editor" })];

  const items = buildDockItems(windows, () => null);

  assert.equal(items[0].pinnable, false);
});

test("a Pin with no Windows shows its App without a Letter Tile and isn't missing", () => {
  const items = buildDockItems(
    [],
    () => null,
    ["firefox"],
    (id) => ({ id, icon: "firefox-icon" }),
  );

  assert.deepEqual(describeItems(items), ["pin:firefox"]);
  assert.equal(items[0].app.id, "firefox");
  assert.equal(items[0].letter, null);
  assert.equal(items[0].missing, false);
});

test("while a pinned App has Windows, their Window Items occupy the Pin's slot instead of a bare Pin", () => {
  const windows = [makeWindow({ id: "firefox-1", class: "firefox" })];

  const items = buildDockItems(
    windows,
    resolveBrowserAndTerminal,
    ["firefox"],
    (id) => ({ id }),
  );

  assert.deepEqual(describeItems(items), ["window:firefox-1"]);
});

test("multiple Windows of a pinned App occupy its slot together, in Launch Order", () => {
  const windows = [
    makeWindow({ id: "firefox-2", class: "firefox", openedAt: 2 }),
    makeWindow({ id: "firefox-1", class: "firefox", openedAt: 1 }),
  ];

  const items = buildDockItems(
    windows,
    resolveBrowserAndTerminal,
    ["firefox"],
    (id) => ({ id }),
  );

  assert.deepEqual(describeItems(items), ["window:firefox-1", "window:firefox-2"]);
});

test("when the last Window of a pinned App closes, the Pin returns at the same slot", () => {
  const resolveAppById = (id) => ({ id });
  const withWindow = buildDockItems(
    [makeWindow({ id: "firefox-1", class: "firefox" })],
    resolveBrowserAndTerminal,
    ["alacritty", "firefox"],
    resolveAppById,
  );
  const withoutWindow = buildDockItems(
    [],
    resolveBrowserAndTerminal,
    ["alacritty", "firefox"],
    resolveAppById,
  );

  assert.deepEqual(describeItems(withWindow), ["pin:alacritty", "window:firefox-1"]);
  assert.deepEqual(describeItems(withoutWindow), ["pin:alacritty", "pin:firefox"]);
});

test("a Pin whose App is no longer installed shows a Letter Tile and is reported as missing", () => {
  const items = buildDockItems([], () => null, ["ghost-app"], () => null);

  assert.equal(items[0].app, null);
  assert.equal(items[0].missing, true);
  assert.equal(items[0].letter, "g");
});

test("Pins occupy the Dock's leading slots in their persisted order, ahead of every unpinned Window in Launch Order", () => {
  const windows = [
    makeWindow({ id: "unpinned-1", class: "btop", openedAt: 1 }),
    makeWindow({ id: "firefox-1", class: "firefox", openedAt: 2 }),
  ];

  const items = buildDockItems(
    windows,
    resolveBrowserAndTerminal,
    ["alacritty", "firefox"],
    (id) => ({ id }),
  );

  assert.deepEqual(describeItems(items), [
    "pin:alacritty",
    "window:firefox-1",
    "window:unpinned-1",
  ]);
});

test("a Window Item occupying a pinned App's slot is reported as pinned", () => {
  const windows = [makeWindow({ id: "firefox-1", class: "firefox" })];

  const items = buildDockItems(
    windows,
    resolveBrowserAndTerminal,
    ["firefox"],
    (id) => ({ id }),
  );

  assert.equal(items[0].pinned, true);
});

test("a Window Item whose App is not pinned is reported as not pinned", () => {
  const windows = [makeWindow({ id: "w1", class: "firefox" })];

  const items = buildDockItems(windows, resolveBrowserAndTerminal);

  assert.equal(items[0].pinned, false);
});

test("an empty Pins list reproduces plain Launch Order, unchanged from before Pins existed", () => {
  const windows = [
    makeWindow({ id: "w1", class: "firefox", openedAt: 1 }),
    makeWindow({ id: "w2", class: "alacritty", openedAt: 2 }),
  ];

  const withEmptyPins = buildDockItems(windows, resolveBrowserAndTerminal, [], () => null);
  const withoutPinsArgs = buildDockItems(windows, resolveBrowserAndTerminal);

  assert.deepEqual(describeItems(withEmptyPins), describeItems(withoutPinsArgs));
});

test("menuFor reports Pin (not yet pinned) for a Window Item with a resolvable App", () => {
  const windows = [makeWindow({ id: "w1", class: "firefox" })];
  const items = buildDockItems(windows, resolveBrowserAndTerminal);

  const menu = menuFor(items[0]);

  assert.deepEqual(menu, {
    pinned: false,
    canPin: true,
    canLaunch: true,
    canClose: true,
  });
});

test("menuFor reports Unpin for a Window Item occupying a pinned App's slot", () => {
  const windows = [makeWindow({ id: "firefox-1", class: "firefox" })];
  const items = buildDockItems(
    windows,
    resolveBrowserAndTerminal,
    ["firefox"],
    (id) => ({ id }),
  );

  const menu = menuFor(items[0]);

  assert.deepEqual(menu, {
    pinned: true,
    canPin: true,
    canLaunch: true,
    canClose: true,
  });
});

test("menuFor disables Pin, launch, but not close, for a Letter Tile Window Item", () => {
  const windows = [makeWindow({ id: "w1", class: "Unknown-Editor" })];
  const items = buildDockItems(windows, () => null);

  const menu = menuFor(items[0]);

  assert.deepEqual(menu, {
    pinned: false,
    canPin: false,
    canLaunch: false,
    canClose: true,
  });
});

test("menuFor reports Unpin and disables Close Window for a Pin with no Windows", () => {
  const items = buildDockItems([], () => null, ["firefox"], (id) => ({ id }));

  const menu = menuFor(items[0]);

  assert.deepEqual(menu, {
    pinned: true,
    canPin: true,
    canLaunch: true,
    canClose: false,
  });
});

test("menuFor still allows Unpin, but disables launch and close, for a Pin whose App is missing", () => {
  const items = buildDockItems([], () => null, ["ghost-app"], () => null);

  const menu = menuFor(items[0]);

  assert.deepEqual(menu, {
    pinned: true,
    canPin: true,
    canLaunch: false,
    canClose: false,
  });
});

test("every Window Item and Pin Item carries a stable key for Placed positions", () => {
  const windows = [makeWindow({ id: "w1", class: "firefox" })];
  const withoutPin = buildDockItems(windows, resolveBrowserAndTerminal);
  const pinOnly = buildDockItems([], () => null, ["alacritty"], (id) => ({ id }));

  assert.equal(withoutPin[0].key, "window:w1");
  assert.equal(pinOnly[0].key, "pin:alacritty");
});

test("a Placed Item is moved to its recorded index, out of its default Launch-Order/Pin-slot position", () => {
  const windows = [
    makeWindow({ id: "w1", class: "firefox", openedAt: 1 }),
    makeWindow({ id: "w2", class: "alacritty", openedAt: 2 }),
  ];

  const items = buildDockItems(windows, resolveBrowserAndTerminal, [], undefined, [
    { key: "window:w2", index: 0 },
  ]);

  assert.deepEqual(itemIds(items), ["w2", "w1"]);
});

test("a Placed Pin keeps an explicit index across separate buildDockItems calls, as a restart would make", () => {
  const placements = [{ key: "pin:firefox", index: 1 }];
  const windows = [makeWindow({ id: "btop-1", class: "btop", openedAt: 1 })];
  const resolveAppById = (id) => ({ id });

  const firstRun = buildDockItems(windows, () => null, ["firefox"], resolveAppById, placements);
  const secondRun = buildDockItems(windows, () => null, ["firefox"], resolveAppById, placements);

  assert.deepEqual(describeItems(firstRun), ["window:btop-1", "pin:firefox"]);
  assert.deepEqual(describeItems(secondRun), ["window:btop-1", "pin:firefox"]);
});

test("a Placed Pin's position reasserts itself once its App's last Window closes and the bare Pin Item returns", () => {
  const placements = [{ key: "pin:firefox", index: 0 }];
  const resolveAppById = (id) => ({ id });
  const windows = [
    makeWindow({ id: "btop-1", class: "btop", openedAt: 1 }),
    makeWindow({ id: "firefox-1", class: "firefox", openedAt: 2 }),
  ];

  const whileOpen = buildDockItems(windows, resolveBrowserAndTerminal, ["firefox"], resolveAppById, placements);
  const afterClose = buildDockItems([windows[0]], resolveBrowserAndTerminal, ["firefox"], resolveAppById, placements);

  // While firefox-1 is open there is no bare "pin:firefox" Item for the
  // placement to match, so the placement is silently ignored and ordering
  // falls back to the Pin-slot default (docs/SPEC.md "Ordering").
  assert.deepEqual(describeItems(whileOpen), ["window:firefox-1", "window:btop-1"]);
  assert.deepEqual(describeItems(afterClose), ["pin:firefox", "window:btop-1"]);
});

test("a Placed Window Item keeps its own index while its Window stays open, unaffected by other Windows opening", () => {
  const placements = [{ key: "window:w1", index: 2 }];
  const withOneWindow = buildDockItems(
    [makeWindow({ id: "w1", class: "firefox", openedAt: 1 })],
    resolveBrowserAndTerminal,
    [],
    undefined,
    placements,
  );
  const withTwoWindows = buildDockItems(
    [
      makeWindow({ id: "w1", class: "firefox", openedAt: 1 }),
      makeWindow({ id: "w2", class: "alacritty", openedAt: 2 }),
    ],
    resolveBrowserAndTerminal,
    [],
    undefined,
    placements,
  );

  assert.deepEqual(itemIds(withOneWindow), ["w1"]);
  assert.deepEqual(itemIds(withTwoWindows), ["w2", "w1"]);
});

test("a Placed Window Item's placement is silently dropped once its Window closes, rather than reappearing as a ghost Item", () => {
  const placements = [{ key: "window:closed-1", index: 0 }];
  const windows = [makeWindow({ id: "w1", class: "firefox", openedAt: 1 })];

  const items = buildDockItems(windows, resolveBrowserAndTerminal, [], undefined, placements);

  assert.deepEqual(itemIds(items), ["w1"]);
});

test("dragging one Window of a pinned App moves only that Window, leaving its sibling Windows in the Pin's slot", () => {
  const resolveAppById = (id) => ({ id });
  const windows = [
    makeWindow({ id: "firefox-1", class: "firefox", openedAt: 1 }),
    makeWindow({ id: "firefox-2", class: "firefox", openedAt: 2 }),
    makeWindow({ id: "btop-1", class: "btop", openedAt: 3 }),
  ];

  const items = buildDockItems(
    windows,
    resolveBrowserAndTerminal,
    ["firefox"],
    resolveAppById,
    [{ key: "window:firefox-2", index: 2 }],
  );

  assert.deepEqual(itemIds(items), ["firefox-1", "btop-1", "firefox-2"]);
});

test("dragging an Item whose App is pinned out of the Dock unpins the App and drops its Pin's Placed position, leaving its Windows as ordinary Window Items", () => {
  const resolveAppById = (id) => ({ id });
  const windows = [makeWindow({ id: "firefox-1", class: "firefox", openedAt: 1 })];
  const entry = { pins: ["firefox"], placements: [{ key: "pin:firefox", index: 0 }] };

  const afterDragOut = effectiveView(applyIntent(entry, { type: "unpinAppFromDrag", appId: "firefox" }));
  const pinsAfterDragOut = afterDragOut.pins;
  const items = buildDockItems(windows, resolveBrowserAndTerminal, pinsAfterDragOut, resolveAppById, afterDragOut.placements);

  assert.deepEqual(pinsAfterDragOut, []);
  assert.equal(items[0].pinned, false);
  assert.deepEqual(menuFor(items[0]), { pinned: false, canPin: true, canLaunch: true, canClose: true });
});

test("dragging an unpinned Window Item out of the Dock snaps back: with no placement or Pins change made, the Dock's Items are unaffected", () => {
  const windows = [
    makeWindow({ id: "w1", class: "firefox", openedAt: 1 }),
    makeWindow({ id: "w2", class: "alacritty", openedAt: 2 }),
  ];

  const before = buildDockItems(windows, resolveBrowserAndTerminal);
  const after = buildDockItems(windows, resolveBrowserAndTerminal);

  assert.deepEqual(describeItems(before), describeItems(after));
});

// --- Grouped windows (docs/SPEC.md "Grouping") --------------------------------

function grouped(windows, resolveApp, pins, resolveAppById, placements) {
  return buildDockItems(windows, resolveApp, pins, resolveAppById, placements, true);
}

test("grouping off leaves every Window as its own Item", () => {
  const items = buildDockItems(
    [
      makeWindow({ id: "a", class: "firefox", openedAt: 1 }),
      makeWindow({ id: "b", class: "firefox", openedAt: 2 }),
    ],
    resolveBrowserAndTerminal,
  );
  assert.deepEqual(itemIds(items), ["a", "b"]);
  assert.equal(items[0].windows, undefined);
});

test("grouping folds the Windows of one App into a single Group Item", () => {
  const items = grouped(
    [
      makeWindow({ id: "a", class: "firefox", openedAt: 1 }),
      makeWindow({ id: "t", class: "alacritty", openedAt: 2 }),
      makeWindow({ id: "b", class: "firefox", openedAt: 3 }),
    ],
    resolveBrowserAndTerminal,
  );
  assert.equal(items.length, 2);
  assert.equal(items[0].kind, "window");
  assert.equal(items[0].key, "group:app:firefox");
  assert.deepEqual(items[0].windows.map((w) => w.id), ["a", "b"]);
  assert.equal(items[0].count, 2);
  assert.equal(items[1].key, "window:t");
  assert.equal(items[1].count, 1);
});

test("a Group Item stands for its most recent Window unless one is Active", () => {
  const windows = [
    makeWindow({ id: "a", class: "firefox", openedAt: 1 }),
    makeWindow({ id: "b", class: "firefox", openedAt: 2 }),
  ];
  assert.equal(grouped(windows, resolveBrowserAndTerminal)[0].window.id, "b");

  windows[0].active = true;
  const item = grouped(windows, resolveBrowserAndTerminal)[0];
  assert.equal(item.window.id, "a");
  assert.equal(item.active, true);
});

test("a Group Item shows Attention when any of its Windows asks for it", () => {
  const item = grouped(
    [
      makeWindow({ id: "a", class: "firefox", openedAt: 1, attention: true }),
      makeWindow({ id: "b", class: "firefox", openedAt: 2 }),
    ],
    resolveBrowserAndTerminal,
  )[0];
  assert.equal(item.attention, true);
});

test("a Group Item's workspace badge is shown only when its Windows share a workspace", () => {
  const same = grouped(
    [
      makeWindow({ id: "a", class: "firefox", workspace: "2", openedAt: 1 }),
      makeWindow({ id: "b", class: "firefox", workspace: "2", openedAt: 2 }),
    ],
    resolveBrowserAndTerminal,
  )[0];
  assert.equal(same.badge, "2");

  const mixed = grouped(
    [
      makeWindow({ id: "a", class: "firefox", workspace: "2", openedAt: 1 }),
      makeWindow({ id: "b", class: "firefox", workspace: "3", openedAt: 2 }),
    ],
    resolveBrowserAndTerminal,
  )[0];
  assert.equal(mixed.badge, "");
});

test("Windows with no App group by window class", () => {
  const items = grouped(
    [
      makeWindow({ id: "a", class: "mystery", openedAt: 1 }),
      makeWindow({ id: "b", class: "mystery", openedAt: 2 }),
      makeWindow({ id: "c", class: "other", openedAt: 3 }),
    ],
    resolveBrowserAndTerminal,
  );
  assert.equal(items.length, 2);
  assert.equal(items[0].count, 2);
  assert.equal(items[0].pinnable, false);
});

test("a pinned App's Windows form one Group Item in the Pin's slot", () => {
  const items = grouped(
    [
      makeWindow({ id: "t", class: "alacritty", openedAt: 1 }),
      makeWindow({ id: "a", class: "firefox", openedAt: 2 }),
      makeWindow({ id: "b", class: "firefox", openedAt: 3 }),
    ],
    resolveBrowserAndTerminal,
    ["firefox"],
    (id) => ({ id }),
  );
  assert.deepEqual(items.map((i) => i.key), ["group:app:firefox", "window:t"]);
  assert.equal(items[0].pinned, true);
});

test("a Placed Group Item keeps its position by the group's key", () => {
  const items = grouped(
    [
      makeWindow({ id: "a", class: "firefox", openedAt: 1 }),
      makeWindow({ id: "b", class: "firefox", openedAt: 2 }),
      makeWindow({ id: "t", class: "alacritty", openedAt: 3 }),
    ],
    resolveBrowserAndTerminal,
    [],
    null,
    [{ key: "group:app:firefox", index: 1 }],
  );
  assert.deepEqual(items.map((i) => i.key), ["window:t", "group:app:firefox"]);
});

// A drop: the Items as shown, the Placed positions, the key moved and the
// index it lands on. The result must rebuild to exactly the order shown after
// the move, whatever was Placed before.
const { movedPlacements } = require("../DockModel.js");

function dropped(pins, placements, key, index) {
  const items = buildDockItems([], () => null, pins, (id) => ({ id }), placements);
  const next = movedPlacements(items, placements, key, index);
  const rebuilt = buildDockItems([], () => null, pins, (id) => ({ id }), next);
  const expected = items.map((i) => i.key).filter((k) => k !== key);
  expected.splice(index, 0, key);
  return { next, order: rebuilt.map((i) => i.key), expected };
}

test("a drop lands where it was dropped when another Item was Placed earlier", () => {
  // d was Placed at 1: shown [a, d, b, c]; dragging a to the end must give [d, b, c, a]
  const { order, expected } = dropped(["a", "b", "c", "d"], [{ key: "pin:d", index: 1 }], "pin:a", 3);
  assert.deepEqual(expected, ["pin:d", "pin:b", "pin:c", "pin:a"]);
  assert.deepEqual(order, expected);
});

test("a drop lands as shown for every Item, slot and earlier Placed position", () => {
  const pins = ["a", "b", "c", "d", "e"];
  const earlier = [[], [{ key: "pin:e", index: 0 }], [{ key: "pin:b", index: 3 }, { key: "pin:e", index: 1 }]];
  for (const placements of earlier) {
    for (const key of pins.map((p) => "pin:" + p)) {
      for (let index = 0; index < pins.length; index++) {
        const { order, expected } = dropped(pins, placements, key, index);
        assert.deepEqual(order, expected, `${key} to ${index} after ${JSON.stringify(placements)}`);
      }
    }
  }
});

test("a drop keeps the Placed position of a Pin currently hidden behind its App's Windows", () => {
  const items = buildDockItems([], () => null, ["a", "b"], (id) => ({ id }), []);
  const next = movedPlacements(items, [{ key: "pin:gone", index: 4 }], "pin:b", 0);
  assert.deepEqual(next.find((p) => p.key === "pin:gone"), { key: "pin:gone", index: 4 });
  assert.deepEqual(next.find((p) => p.key === "pin:b"), { key: "pin:b", index: 0 });
});

test("clipText caps a window's title or class and copes with non-strings", () => {
  const { clipText, MAX_WINDOW_TEXT } = require("../DockModel.js");
  assert.equal(clipText("short"), "short");
  assert.equal(clipText("x".repeat(MAX_WINDOW_TEXT + 500)).length, MAX_WINDOW_TEXT);
  assert.equal(clipText("abcdef", 3), "abc");
  assert.equal(clipText(undefined), "");
  assert.equal(clipText(null), "");
  assert.equal(clipText(42), "");
});

test("chromeAppClass maps a Chromium-family web app class to the chrome- one Omarchy's entries name", () => {
  const { chromeAppClass } = require("../DockModel.js");
  assert.equal(chromeAppClass("msedge-x.com__-Default"), "chrome-x.com__-Default");
  assert.equal(chromeAppClass("brave-discord.com__channels_@me-Default"), "chrome-discord.com__channels_@me-Default");
  assert.equal(chromeAppClass("chrome-x.com__-Default"), null);
  assert.equal(chromeAppClass("msedge"), null);
  assert.equal(chromeAppClass("microsoft-edge"), null);
  assert.equal(chromeAppClass(""), null);
  assert.equal(chromeAppClass(undefined), null);
});
