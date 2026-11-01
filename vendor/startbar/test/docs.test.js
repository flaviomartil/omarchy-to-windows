// Keeps the docs and the code in step where a mismatch is mechanical:
// settings without a row in the reference, comments citing a spec section
// that no longer exists, version files that disagree, and theme colours used
// where the colour scheme should apply. See CONTRIBUTING.md "Checks".
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const DockConfig = require("../DockConfig.js");

const root = path.join(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const sourceFiles = () =>
  fs.readdirSync(root).filter((name) => /\.(qml|js)$/.test(name))
    .concat(fs.readdirSync(path.join(root, "test")).filter((name) => name !== "docs.test.js").map((name) => "test/" + name));

test("every setting in the settings window has a row in docs/SETTINGS.md", () => {
  const reference = read("docs/SETTINGS.md");
  const keys = DockConfig.settingsSchema().flatMap((group) => group.fields.map((field) => field.key));
  assert.ok(keys.length > 0);
  const missing = keys.filter((key) => !reference.includes("`" + key + "`"));
  assert.deepEqual(missing, [], "add these keys to a table in docs/SETTINGS.md");
});

test("every SPEC.md section a comment cites exists in docs/SPEC.md", () => {
  const spec = read("docs/SPEC.md");
  const sections = new Set();
  for (const line of spec.split("\n")) {
    const heading = line.match(/^#+ (.+)$/);
    if (heading) sections.add(heading[1]);
    const label = line.match(/^- ([A-Z][A-Za-z ]+):/);
    if (label) sections.add(label[1]);
  }
  const broken = [];
  for (const file of sourceFiles()) {
    // Citations wrap across comment lines, so read the comments as one run of text.
    const text = read(file).replace(/\n\s*\/\/ ?/g, " ");
    for (const match of text.matchAll(/SPEC\.md,? "([^"]+)"((?:, "[^"]+")*)/g)) {
      const cited = [match[1]].concat([...match[2].matchAll(/"([^"]+)"/g)].map((more) => more[1]));
      for (const name of cited) {
        if (!sections.has(name)) broken.push(file + ': SPEC.md "' + name + '"');
      }
    }
  }
  assert.deepEqual(broken, [], "cite a heading or a bullet label that exists in docs/SPEC.md (found: " + [...sections].join(", ") + ")");
});

test("manifest.json and package.json carry the same version", () => {
  assert.equal(JSON.parse(read("package.json")).version, JSON.parse(read("manifest.json")).version);
});

// colorScheme (docs/SPEC.md "The bar") must reach the Dock and everything
// that rises from it. Those parts take their colours from the palette
// properties (root.col* in Service.qml, startMenu.col* in StartMenuView.qml),
// which fall back to the theme; a bare Color.* there ignores a light or dark
// scheme. Color.urgent is the theme's own Attention colour in every scheme.
test("the Dock and what rises from it take colours from the palette, not the theme", () => {
  const offenders = [];
  const check = (file, lines, firstLine) => {
    lines.forEach((line, index) => {
      const code = line.replace(/\/\/.*$/, "");
      if (!/\bColor\./.test(code)) return;
      if (/^\s*readonly property color col\w+:/.test(code)) return;
      if (/\bColor\.(?!urgent\b)/.test(code)) offenders.push(file + ":" + (firstLine + index) + ": " + line.trim());
    });
  };
  check("StartMenuView.qml", read("StartMenuView.qml").split("\n"), 1);
  const service = read("Service.qml").split("\n");
  const perMonitor = service.findIndex((line) => /^  Variants \{/.test(line));
  assert.ok(perMonitor > 0, "Service.qml no longer has the per-monitor Variants block this test looks for");
  check("Service.qml", service.slice(perMonitor), perMonitor + 1);
  assert.deepEqual(offenders, [], "use root.col* (Service.qml) or startMenu.col* (StartMenuView.qml) instead");
});
