const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// Qt's default Text.AutoText renders anything that looks like HTML as rich
// text, and rich text loads <img> files synchronously: a window title, an App
// name or a pasted string could name a FIFO nobody writes to and hang the
// shell. So every Text the plugin draws says it is plain.
const root = path.join(__dirname, "..");
const files = fs.readdirSync(root).filter((name) => name.endsWith(".qml"));

for (const file of files) {
  test(`${file}: every Text is Text.PlainText`, () => {
    const lines = fs.readFileSync(path.join(root, file), "utf8").split("\n");
    const missing = [];
    lines.forEach((line, i) => {
      if (!/^\s*Text \{/.test(line)) return;
      const here = line.includes("textFormat:");
      const next = i + 1 < lines.length && /^\s*textFormat: Text\.PlainText\s*$/.test(lines[i + 1]);
      if (!here && !next) missing.push(`${file}:${i + 1}`);
      if (here && !line.includes("Text.PlainText")) missing.push(`${file}:${i + 1} (not PlainText)`);
    });
    assert.deepEqual(missing, []);
  });
}

test("no Text is declared on a line the check cannot read", () => {
  for (const file of files) {
    const text = fs.readFileSync(path.join(root, file), "utf8");
    const all = (text.match(/\bText \{/g) || []).length;
    const readable = (text.match(/^\s*Text \{/gm) || []).length;
    assert.equal(readable, all, `${file}: put each Text { on its own line, indented`);
  }
});
