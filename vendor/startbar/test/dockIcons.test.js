const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const I = require("../DockIcons.js");

test("searchCommand is a bash -lc argv with the name as an argument, not in the script", () => {
  const argv = I.searchCommand("org.remmina.Remmina");
  assert.deepEqual(argv.slice(0, 2), ["bash", "-lc"]);
  assert.equal(argv[3], "bash");
  assert.equal(argv[4], "org.remmina.Remmina");
  assert.ok(!argv[2].includes("Remmina"));
  assert.equal(spawnSync("bash", ["-n"], { input: argv[2] }).status, 0);
});

test("searchCommand refuses names that are paths or contain glob characters", () => {
  for (const name of ["/usr/share/pixmaps/x.png", "a*b", "a b", "../x", "", null, undefined, 3]) {
    assert.equal(I.searchCommand(name), null, String(name));
  }
});

test("the script finds a png and an svg in XDG_DATA_HOME and XDG_DATA_DIRS", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "icons-"));
  const dirs = fs.mkdtempSync(path.join(os.tmpdir(), "icons-"));
  fs.mkdirSync(path.join(home, "icons/hicolor/48x48/apps"), { recursive: true });
  fs.mkdirSync(path.join(dirs, "pixmaps"), { recursive: true });
  fs.writeFileSync(path.join(home, "icons/hicolor/48x48/apps/found-me.png"), "");
  fs.writeFileSync(path.join(dirs, "pixmaps/found-me.svg"), "");
  fs.writeFileSync(path.join(dirs, "pixmaps/other.png"), "");
  const argv = I.searchCommand("found-me");
  const result = spawnSync(argv[0], argv.slice(1), {
    encoding: "utf8",
    env: { ...process.env, XDG_DATA_HOME: home, XDG_DATA_DIRS: dirs },
  });
  const lines = result.stdout.trim().split("\n").sort();
  assert.deepEqual(lines, [path.join(dirs, "pixmaps/found-me.svg"), path.join(home, "icons/hicolor/48x48/apps/found-me.png")].sort());
});

test("the script prints nothing, and succeeds, when there is no such icon", () => {
  const argv = I.searchCommand("no-such-icon-anywhere");
  const result = spawnSync(argv[0], argv.slice(1), { encoding: "utf8" });
  assert.equal(result.stdout, "");
  assert.equal(result.status, 0);
});

test("pickBest prefers a scalable file, then the largest size", () => {
  assert.equal(I.pickBest("/i/hicolor/48x48/apps/x.png\n/i/hicolor/scalable/apps/x.svg\n/i/hicolor/512x512/apps/x.png\n"), "/i/hicolor/scalable/apps/x.svg");
  assert.equal(I.pickBest("/i/hicolor/48x48/apps/x.png\n/i/hicolor/512x512/apps/x.png\n/i/hicolor/128x128/apps/x.png"), "/i/hicolor/512x512/apps/x.png");
  assert.equal(I.pickBest("/usr/share/pixmaps/x.png\n/i/hicolor/22x22/apps/x.png"), "/i/hicolor/22x22/apps/x.png");
  assert.equal(I.pickBest("/usr/share/pixmaps/x.png"), "/usr/share/pixmaps/x.png");
});

test("pickBest gives '' for no output", () => {
  assert.equal(I.pickBest(""), "");
  assert.equal(I.pickBest("\n"), "");
  assert.equal(I.pickBest(undefined), "");
});

test("a name never searched for is searched for at once", () => {
  assert.equal(I.shouldSearch(0, 0, 5), true);
  assert.equal(I.shouldSearch(undefined, undefined, 5), true);
});

test("a missing name is searched for again only after RETRY_MS, and MAX_TRIES times at most", () => {
  assert.equal(I.shouldSearch(1, 1000, 1000 + I.RETRY_MS - 1), false);
  assert.equal(I.shouldSearch(1, 1000, 1000 + I.RETRY_MS), true);
  assert.equal(I.shouldSearch(I.MAX_TRIES - 1, 0, I.RETRY_MS), true);
  assert.equal(I.shouldSearch(I.MAX_TRIES, 0, 100 * I.RETRY_MS), false);
});
