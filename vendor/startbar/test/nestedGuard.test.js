// The test session and the tour recorder (scripts/nested/session.sh) run the plugin in a second desktop that shares this user's systemd,
// login session and system bus, so a click on the Start menu's Shut down, Restart, Sleep, Sign out or Lock would act on the real
// machine. The guard in front of the session's PATH refuses those commands. These tests build the guard in a throwaway folder and
// check it refuses them and writes down what it refused. systemctl and loginctl are replaced by stand-ins that only say they were
// reached, so a fault in the guard fails a test instead of reaching the machine.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const session = path.join(root, "scripts", "nested", "session.sh");
const StartMenu = require("../StartMenu.js");

// Builds the guard in a new folder and returns what the test needs to run its commands.
function build() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "guard-test-"));
  const standIn = (name) => {
    const file = path.join(tmp, "real-" + name);
    fs.writeFileSync(file, `#!/bin/bash\necho "reached the real ${name} $*" >>${JSON.stringify(path.join(tmp, "reached.log"))}\n`, { mode: 0o755 });
    return file;
  };
  const env = { ...process.env, GUARD_SYSTEMCTL: standIn("systemctl"), GUARD_LOGINCTL: standIn("loginctl") };
  const script = `
    set -u
    TMP=${JSON.stringify(tmp)}; REPO=${JSON.stringify(root)}; HERE=${JSON.stringify(path.join(root, "scripts"))}
    source ${JSON.stringify(session)}
    mkdir -p "$NEST_HOME" "$NEST_BIN"
    sandbox_guard
    guard_check
  `;
  const built = spawnSync("bash", ["-c", script], { env, encoding: "utf8" });
  const guard = path.join(tmp, "nest", "bin", "guard");
  const log = path.join(tmp, "nest", "guard.log");
  const reached = path.join(tmp, "reached.log");
  return {
    tmp, built, guard, env,
    refused: () => (fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean) : []),
    reached: () => (fs.existsSync(reached) ? fs.readFileSync(reached, "utf8").trim().split("\n").filter(Boolean) : []),
    run: (name, ...args) => spawnSync(path.join(guard, name), args, { env, encoding: "utf8" }),
    cleanup: () => fs.rmSync(tmp, { recursive: true, force: true }),
  };
}

test("the guard builds and passes its own check", () => {
  const g = build();
  try {
    assert.equal(g.built.status, 0, g.built.stderr);
  } finally {
    g.cleanup();
  }
});

test("the guard refuses every power command the Start menu can run, and writes down each", () => {
  const g = build();
  try {
    assert.equal(g.built.status, 0, g.built.stderr);
    // Every command behind the user's name and the power button, so a new one added to the menu is held to the guard as well.
    const commands = ["user", "power"]
      .flatMap((kind) => StartMenu.overlayRows({ kind }, {}))
      .map((row) => row.action.command);
    assert.ok(commands.length >= 5, "the Start menu offers Lock, Sign out, Sleep, Restart and Shut down");
    for (const command of commands) {
      // Run as the Start menu runs it: through a login shell, with the guard first on PATH.
      const result = spawnSync("bash", ["-lc", command], {
        env: { ...g.env, PATH: `${g.guard}:${process.env.PATH}`, HOME: path.join(g.tmp, "nest", "home") },
        encoding: "utf8",
      });
      assert.notEqual(result.status, 0, `${command} was not refused`);
      assert.match(result.stderr, /refused/, `${command}: ${result.stderr}`);
    }
    assert.equal(g.refused().length, commands.length, g.refused().join("\n"));
    assert.deepEqual(g.reached(), [], "a refused command reached the real systemctl or loginctl");
  } finally {
    g.cleanup();
  }
});

test("systemctl and loginctl pass on what does not act on the machine", () => {
  const g = build();
  try {
    assert.equal(g.built.status, 0, g.built.stderr);
    assert.equal(g.run("systemctl", "--user", "is-active", "something").status, 0);
    assert.equal(g.run("loginctl", "show-session", "self").status, 0);
    assert.equal(g.reached().length, 2);
    assert.deepEqual(g.refused(), []);
  } finally {
    g.cleanup();
  }
});

test("systemctl and loginctl refuse the verbs that act on the machine, wherever they are among the arguments", () => {
  const g = build();
  try {
    assert.equal(g.built.status, 0, g.built.stderr);
    const cases = [
      ["systemctl", "poweroff"], ["systemctl", "--no-wall", "reboot"], ["systemctl", "suspend"], ["systemctl", "hibernate"],
      ["systemctl", "--user", "exit"], ["systemctl", "reboot", "--boot-loader-menu=0"], ["loginctl", "lock-session"],
      ["loginctl", "terminate-user", "me"], ["loginctl", "poweroff"],
    ];
    for (const [program, ...args] of cases) {
      const result = g.run(program, ...args);
      assert.notEqual(result.status, 0, `${program} ${args.join(" ")} was not refused`);
    }
    assert.equal(g.refused().length, cases.length);
    assert.deepEqual(g.reached(), []);
  } finally {
    g.cleanup();
  }
});

test("the guard refuses every omarchy-system command, with any arguments", () => {
  const g = build();
  try {
    assert.equal(g.built.status, 0, g.built.stderr);
    for (const name of ["omarchy-system", "omarchy-system-lock", "omarchy-system-sleep-lock", "poweroff", "reboot", "shutdown", "hyprlock", "uwsm"]) {
      assert.notEqual(g.run(name, "anything", "at", "all").status, 0, name);
    }
  } finally {
    g.cleanup();
  }
});
