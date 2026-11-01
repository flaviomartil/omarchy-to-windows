const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const H = require("../DockHyprland.js");
const { windowActions } = require("../DockModel.js");

const ADDR = "0x56538020a4f0";
const scriptOf = (argv) => argv[2];

// Every command the module can produce, for the syntax check.
const all = {
  focusWindow: H.focusWindow(ADDR),
  focusWindowAndWarp: H.focusWindowAndWarp(ADDR),
  closeWindow: H.closeWindow(ADDR),
  minimizeWindow: H.minimizeWindow(ADDR),
  peekWindow: H.peekWindow(ADDR),
  peekRestore: H.peekRestore(),
  peekCommit: H.peekCommit(),
  rescueWindows: H.rescueWindows([ADDR, "0xabc"]),
  glassRule: H.glassRule(),
  openOnOwnWorkspace: H.openOnOwnWorkspace(ADDR, "maximized"),
  openOnOwnWorkspaceFullscreen: H.openOnOwnWorkspace(ADDR, "fullscreen"),
  openOnOwnWorkspaceNormal: H.openOnOwnWorkspace(ADDR, "normal"),
};
for (const id of H.windowActionIds) all["windowAction " + id] = H.windowAction(id, ADDR);

for (const [name, argv] of Object.entries(all)) {
  test(`${name} is a bash -lc argv whose script parses`, () => {
    assert.deepEqual(argv.slice(0, 2), ["bash", "-lc"]);
    assert.equal(argv[3], "bash");
    const result = spawnSync("bash", ["-n"], { input: scriptOf(argv) });
    assert.equal(result.status, 0, result.stderr.toString());
  });
}

test("addresses are normalized and never spliced into a script", () => {
  assert.equal(H.normalizedAddress("56538020a4f0"), ADDR);
  assert.equal(H.normalizedAddress(ADDR), ADDR);
  assert.equal(H.normalizedAddress("0x"), null);
  assert.equal(H.normalizedAddress("x; rm -rf ~"), null);
  assert.equal(H.normalizedAddress(null), null);
  const argv = H.focusWindow("56538020a4f0");
  assert.equal(argv[4], ADDR);
  assert.ok(!scriptOf(argv).includes("56538020a4f0"));
});

test("a bad address produces no command", () => {
  for (const fn of [H.focusWindow, H.focusWindowAndWarp, H.closeWindow, H.minimizeWindow, H.peekWindow]) {
    assert.equal(fn("not hex"), null);
  }
  assert.equal(H.windowAction("maximize", "nope"), null);
});

test("focusing keeps the pointer put and raises a floating Window", () => {
  const script = scriptOf(all.focusWindow);
  assert.match(script, /no_warps = true/);
  assert.match(script, /hl\.dsp\.focus\(\{ window = \\"address:\$addr\\" \}\)/);
  assert.match(script, /raise "\$addr"/);
  assert.match(script, /no_warps = \$orig/);
});

test("focus-and-warp moves the pointer to the Window instead", () => {
  const script = scriptOf(all.focusWindowAndWarp);
  assert.match(script, /hl\.dsp\.cursor\.move/);
  assert.doesNotMatch(script, /no_warps/);
});

test("every Window-state row has a dispatch aimed by address, and no others exist", () => {
  const ids = new Set();
  for (const window of [
    { fullscreen: 0, floating: false, workspace: "1" },
    { fullscreen: 1, floating: true, pinned: true, workspace: "1" },
    { fullscreen: 2, floating: true, workspace: "special:scratchpad" },
  ]) for (const a of windowActions(window)) ids.add(a.id);
  assert.deepEqual([...ids].sort(), [...H.windowActionIds].sort());
  for (const id of ids) {
    const argv = H.windowAction(id, ADDR);
    assert.ok(argv[4].includes(`window = "address:${ADDR}"`), id);
    assert.match(argv[4], /^hl\.dsp\.window\./);
  }
  assert.equal(H.windowAction("rm -rf", ADDR), null);
  assert.equal(H.windowAction("constructor", ADDR), null);
});

test("close dispatches window.close at the address argument", () => {
  assert.match(scriptOf(all.closeWindow), /hl\.dsp\.window\.close/);
});

test("minimize targets the addressed Window without following it", () => {
  const argv = H.minimizeWindow(ADDR.slice(2));
  assert.equal(argv[4], ADDR);
  assert.match(scriptOf(argv), /special:minimized/);
  assert.match(scriptOf(argv), /follow = false/);
  assert.match(scriptOf(argv), /address:\$1/);
  assert.equal(H.minimizeWindow('0xabc; touch /tmp/unwanted'), null);
});

test("peek scripts share one lock and one state file", () => {
  for (const name of ["peekWindow", "peekRestore", "peekCommit"]) {
    assert.match(scriptOf(all[name]), /startbar-peek\.lock/, name);
    assert.match(scriptOf(all[name]), /startbar-peek"/, name);
  }
});

test("a first peek saves state, a later one undoes the previous peek first", () => {
  const script = scriptOf(all.peekWindow);
  assert.match(script, /if \[ -f "\$state" \]/);
  assert.ok(script.indexOf("undo\n") < script.indexOf("} > \"$state\""));
});

test("restore puts back state and focus, commit only drops the state", () => {
  const restore = scriptOf(all.peekRestore);
  assert.match(restore, /rm -f "\$state"/);
  assert.match(restore, /focus\(\{ window = \\"address:\$prev\\"/);
  const commit = scriptOf(all.peekCommit);
  assert.match(commit, /flock 9; rm -f /);
  assert.doesNotMatch(commit, /hyprctl/);
});

for (const name of ["focusWindow", "focusWindowAndWarp"]) {
  test(`${name} brings a Window minimized to special:minimized back before focusing it`, () => {
    const script = scriptOf(all[name]);
    assert.match(script, /special:minimized/);
    assert.ok(script.indexOf('restore "$addr"') < script.indexOf("hl.dsp.focus({ window"));
  });
}

test("openOnOwnWorkspace refuses a mode it does not know", () => {
  assert.equal(H.openOnOwnWorkspace(ADDR, "off"), null);
  assert.equal(H.openOnOwnWorkspace(ADDR, "x; rm -rf ~"), null);
  assert.equal(H.openOnOwnWorkspace(ADDR), null);
});

for (const name of ["focusWindow", "focusWindowAndWarp"]) {
  test(`${name} rescues a Window outside every monitor before focusing it`, () => {
    const script = scriptOf(all[name]);
    assert.match(script, /hl\.dsp\.window\.center/);
    assert.ok(script.indexOf('rescue "$addr"') < script.indexOf("hl.dsp.focus({ window"));
  });
}

// Runs the focus script against a stub `hyprctl` that serves the given clients
// and monitors and records each dispatch, and returns the recorded dispatches.
function dispatchesFor(clients, monitors, argv = H.focusWindow(ADDR), jqArguments = []) {
  const fs = require("node:fs");
  const os = require("node:os");
  const path = require("node:path");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "startbar-rescue-"));
  try {
    fs.writeFileSync(path.join(dir, "clients.json"), JSON.stringify(clients));
    fs.writeFileSync(path.join(dir, "monitors.json"), JSON.stringify(monitors));
    fs.writeFileSync(path.join(dir, "jq"),
      '#!/bin/sh\n'
      + `printf '%s\\0' "$@" >> "${dir}/jq-arguments"\n`
      + 'exec /usr/bin/jq "$@"\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, "hyprctl"),
      '#!/bin/sh\n'
      + `case "$1 $2" in\n`
      + `  "-j clients") cat "${dir}/clients.json" ;;\n`
      + `  "-j monitors") cat "${dir}/monitors.json" ;;\n`
      + `  "dispatch "*) echo "$2" >> "${dir}/dispatches" ;;\n`
      + `esac\n`, { mode: 0o755 });
    spawnSync(argv[0], argv.slice(1), { env: { ...process.env, PATH: dir + ":" + process.env.PATH } });
    jqArguments.push(...fs.readFileSync(path.join(dir, "jq-arguments"), "utf8").split("\0").filter(Boolean));
    const file = path.join(dir, "dispatches");
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8").split("\n").filter(Boolean) : [];
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const monitor = (x, scale = 1) => ({ x, y: 0, width: 1920 * scale, height: 1080 * scale, scale });
const client = (at, over = {}) => ({ address: ADDR, floating: true, at, size: [1100, 700], workspace: { name: "2" }, ...over });
const centers = (dispatches) => dispatches.filter((d) => d.includes("window.center"));

for (const name of ["focusWindow", "focusWindowAndWarp", "rescueWindows"]) {
  test(`${name} keeps private window and monitor metadata out of jq arguments`, () => {
    const privateTitle = "PRIVATE_BROWSER_TITLE";
    const privateInitialTitle = "PRIVATE_DOCUMENT_INITIAL_TITLE";
    const privateMonitor = "PRIVATE_MONITOR_DESCRIPTION";
    const jqArguments = [];
    const argv = name === "rescueWindows" ? H.rescueWindows([ADDR]) : H[name](ADDR);
    const dispatches = dispatchesFor([
      client([362, 125], { title: privateTitle }),
      client([2400, 300], { address: "0xabc", initialTitle: privateInitialTitle }),
    ], [{ ...monitor(1920), description: privateMonitor }], argv, jqArguments);
    assert.equal(centers(dispatches).length, 1);
    assert.ok(jqArguments.length > 0);
    for (const value of [privateTitle, privateInitialTitle, privateMonitor]) {
      assert.ok(!jqArguments.some((arg) => arg.includes(value)), "Private metadata was exposed in jq arguments");
    }
  });
}

test("a floating Window outside every monitor is centered", () => {
  assert.equal(centers(dispatchesFor([client([362, 125])], [monitor(1920)])).length, 1);
  assert.equal(centers(dispatchesFor([client([-1100, 125])], [monitor(0)])).length, 1);
  // Only a sliver (40 px) left on the monitor.
  assert.equal(centers(dispatchesFor([client([3800, 100])], [monitor(1920)])).length, 1);
});

test("a Window on some monitor is left where it is", () => {
  assert.equal(centers(dispatchesFor([client([2400, 300])], [monitor(1920)])).length, 0);
  // On the second of two monitors.
  assert.equal(centers(dispatchesFor([client([2400, 300])], [monitor(0), monitor(1920)])).length, 0);
  // Half off the edge, with plenty still showing.
  assert.equal(centers(dispatchesFor([client([3300, 300])], [monitor(1920)])).length, 0);
  // A scaled monitor is measured in layout pixels: 3840 px at scale 2 is 1920 wide.
  assert.equal(centers(dispatchesFor([client([2400, 300])], [{ x: 1920, y: 0, width: 3840, height: 2160, scale: 2 }])).length, 0);
});

test("a tiled Window is never moved, and the focus still goes ahead", () => {
  const dispatches = dispatchesFor([client([362, 125], { floating: false })], [monitor(1920)]);
  assert.equal(centers(dispatches).length, 0);
  assert.ok(dispatches.some((d) => d.includes("hl.dsp.focus({ window")));
});

test("opening a Preview rescues each of its Windows that is outside every monitor", () => {
  const other = "0xabc";
  const clients = [client([362, 125]), client([2400, 300], { address: other }), client([100, 100], { address: "0xdef" })];
  const dispatches = dispatchesFor(clients, [monitor(1920)], H.rescueWindows([ADDR, other]));
  // ADDR is lost and is centered; `other` is on screen; 0xdef is lost but not asked for.
  assert.deepEqual(centers(dispatches).map((d) => d.match(/address:(\w+)/)[1]), [ADDR]);
  assert.equal(H.rescueWindows([]), null);
  assert.equal(H.rescueWindows(["nope"]), null);
});
