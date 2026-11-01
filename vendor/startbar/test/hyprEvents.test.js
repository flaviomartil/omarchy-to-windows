const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const script = path.join(__dirname, "../scripts/hypr-events.sh");
const marker = "SYNTHETIC_PRIVATE_WINDOW_TITLE";

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "startbar-events-test-"));
  const runtime = path.join(directory, "runtime");
  fs.mkdirSync(runtime, { mode: 0o700 });
  fs.writeFileSync(path.join(directory, "socat"), "#!/bin/sh\nprintf '%s\\n' 'openwindow>>0xabc,1,foot," + marker + "'\n", { mode: 0o755 });
  const groups = [];
  return {
    directory,
    runtime,
    start(args, extra = {}) {
      const result = spawnSync("bash", ["-c", 'umask 022; exec bash "$@"', "bash", script, "start", ...args], {
        cwd: directory,
        env: { ...process.env, PATH: directory + ":" + process.env.PATH, XDG_RUNTIME_DIR: runtime, HYPRLAND_INSTANCE_SIGNATURE: "test-instance", ...extra },
        detached: true,
        encoding: "utf8",
        timeout: 3000,
      });
      groups.push(result.pid);
      return result;
    },
    cleanup() {
      for (const group of groups) {
        try { process.kill(-group, "SIGTERM"); } catch (error) { if (error.code !== "ESRCH") throw error; }
      }
      fs.rmSync(directory, { recursive: true, force: true });
    },
  };
}

async function waitFor(check) {
  for (let i = 0; i < 100; i++) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.fail("The synthetic event logger did not finish");
}

function recorded(file) {
  return fs.existsSync(file) && fs.readFileSync(file, "utf8").includes(marker);
}

test("event logs keep private permissions for new and existing files", async () => {
  for (const existing of [false, true]) {
    const f = fixture();
    try {
      const log = path.join(f.directory, "events.log");
      if (existing) fs.writeFileSync(log, "old content", { mode: 0o644 });
      const result = f.start([log]);
      assert.equal(result.status, 0, result.stderr);
      await waitFor(() => recorded(log));
      assert.equal(fs.statSync(log).mode & 0o777, 0o600, "Window events must not be readable by other accounts");
    } finally { f.cleanup(); }
  }
});

test("event logs treat literal filenames as data instead of shell code", async () => {
  const f = fixture();
  try {
    const canary = path.join(f.directory, "injected");
    const log = path.join(f.directory, "events'; printf injected > injected; #");
    const result = f.start([log]);
    assert.equal(result.status, 0, result.stderr);
    await waitFor(() => fs.existsSync(canary) || recorded(log));
    assert.equal(fs.existsSync(canary), false, "A log filename executed a shell command");
    assert.ok(recorded(log));
  } finally { f.cleanup(); }
});

test("the default event log stays in the private runtime directory", async () => {
  const f = fixture();
  try {
    const result = f.start([]);
    assert.equal(result.status, 0, result.stderr);
    const log = path.join(f.runtime, "startbar-events.log");
    await waitFor(() => recorded(log));
    assert.equal(fs.statSync(log).mode & 0o777, 0o600);
    assert.equal(fs.statSync(path.join(f.runtime, "startbar-events.pid")).mode & 0o777, 0o600);
  } finally { f.cleanup(); }
});

test("event logging refuses missing, relative, or shared runtime directories", () => {
  const f = fixture();
  try {
    const shared = path.join(f.directory, "shared");
    fs.mkdirSync(shared);
    fs.chmodSync(shared, 0o777);
    for (const runtime of ["", "runtime", shared]) {
      const log = path.join(f.directory, "not-created.log");
      const result = f.start([log], { XDG_RUNTIME_DIR: runtime });
      assert.notEqual(result.status, 0);
      assert.equal(fs.existsSync(log), false);
    }
  } finally { f.cleanup(); }
});
