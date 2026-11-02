const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const DockHyprland = require("../DockHyprland.js");

const service = fs.readFileSync(path.join(__dirname, "../Service.qml"), "utf8");

for (const name of ["focusWindow", "focusWindowAndWarp"]) {
  test(`${name} keeps a taskbar selection after pending preview work finishes`, () => {
    let focused = "0xabc";
    let saved = focused;
    const pending = [() => { focused = "0xdef"; }];
    const run = (command) => {
      if (command[2].includes("hl.dsp.focus")) focused = command[4];
      else if (command[2].includes("rm -f")) saved = null;
    };
    const context = vm.createContext({
      DockHyprland,
      Quickshell: { execDetached: run },
      root: {
        peekRun: (command) => pending.push(() => run(command)),
        peekCommit: () => pending.push(() => { saved = null; }),
      },
    });
    const source = service.match(new RegExp(`  function ${name}\\(address\\) \\{[\\s\\S]*?^  \\}`, "m"));
    assert.ok(source, `Missing QML handler: ${name}`);
    vm.runInContext(source[0], context);
    vm.runInContext(`${name}("0x123")`, context);
    pending.push(() => { if (saved) focused = saved; });
    while (pending.length) pending.shift()();
    assert.equal(focused, "0x123");
  });
}
