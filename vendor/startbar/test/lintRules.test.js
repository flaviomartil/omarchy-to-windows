// scripts/lint-rules.sh holds the rules no linter knows (see its header). Each is run against a throwaway tree holding the mistake it
// is for, and against the real tree, so a rule that stops catching anything fails here.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const rules = path.join(root, "scripts", "lint-rules.sh");

// A tree with scripts/dev, scripts/tours/x.sh and scripts/x.sh holding the given text.
function tree(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lint-rules-test-"));
  fs.mkdirSync(path.join(dir, "scripts", "tours"), { recursive: true });
  fs.mkdirSync(path.join(dir, "scripts", "nested"), { recursive: true });
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), text);
  return dir;
}
const run = (dir) => spawnSync("bash", [rules], { env: { ...process.env, LINT_RULES_ROOT: dir }, encoding: "utf8" });

test("the project passes its own rules", () => {
  const result = spawnSync("bash", [rules], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test("detached: a setsid -f launch that does not redirect its output is caught", () => {
  const dir = tree({ "scripts/dev": "setsid -f sleep 100\n" });
  try {
    const result = run(dir);
    assert.equal(result.status, 1);
    assert.match(result.stdout, /setsid -f without 2>&1/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("detached: a launch whose redirect is on a continuation line passes, and one without is caught", () => {
  const ok = tree({ "scripts/nested/session.sh": "setsid -f env A=1 \\\n  sleep 100 >/dev/null 2>&1\n" });
  const bad = tree({ "scripts/nested/session.sh": "setsid -f env A=1 \\\n  sleep 100\n" });
  try {
    assert.equal(run(ok).status, 0);
    assert.equal(run(bad).status, 1);
  } finally {
    fs.rmSync(ok, { recursive: true, force: true });
    fs.rmSync(bad, { recursive: true, force: true });
  }
});

test("tours: a sandbox copy or link of the real shell.json is caught, a comment about it is not", () => {
  const bad = tree({ "scripts/tours/x.sh": "TOUR_SANDBOX_COPY=(.config/omarchy/shell.json)\n", "scripts/dev": "" });
  const link = tree({ "scripts/tours/x.sh": "TOUR_SANDBOX_LINK=(.local/share/icons .config/omarchy/shell.json)\n", "scripts/dev": "" });
  const ok = tree({ "scripts/tours/x.sh": "TOUR_SANDBOX_COPY=()   # the sandbox has its own shell.json\n", "scripts/dev": "" });
  try {
    assert.equal(run(bad).status, 1);
    assert.equal(run(link).status, 1);
    assert.equal(run(ok).status, 0);
  } finally {
    for (const dir of [bad, link, ok]) fs.rmSync(dir, { recursive: true, force: true });
  }
});
