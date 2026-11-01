const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const P = require("../PlainText.js");

const key = (over) => ({ key: "other", ctrl: false, ctrlOnly: false, text: "", ...over });

test("pasteCommand is a bash -lc script that parses, with a timeout and a byte cap", () => {
  const argv = P.pasteCommand();
  assert.deepEqual(argv.slice(0, 2), ["bash", "-lc"]);
  assert.equal(spawnSync("bash", ["-n"], { input: argv[2] }).status, 0);
  assert.match(argv[2], /timeout 1 wl-paste/);
  assert.match(argv[2], new RegExp("head -c " + P.MAX_PASTE_BYTES));
});

test("the paste command stops a clipboard that never ends", () => {
  // A stand-in provider that streams forever: the same pipeline must end quickly.
  const script = "timeout 1 yes | head -c " + P.MAX_PASTE_BYTES + " | wc -c";
  const started = Date.now();
  const result = spawnSync("bash", ["-c", script], { encoding: "utf8" });
  assert.equal(Number(result.stdout.trim()), P.MAX_PASTE_BYTES);
  assert.ok(Date.now() - started < 3000);
});

test("cleanPaste turns line breaks and tabs into spaces and drops control characters", () => {
  assert.equal(P.cleanPaste("a\nb\r\nc\td", 100), "a b c d");
  assert.equal(P.cleanPaste("a\u0007b\u001bc\u007fd", 100), "abcd");
});

test("cleanPaste cuts to the room left and copes with nothing", () => {
  assert.equal(P.cleanPaste("abcdef", 3), "abc");
  assert.equal(P.cleanPaste("abcdef", 0), "");
  assert.equal(P.cleanPaste("abcdef", -4), "");
  assert.equal(P.cleanPaste(undefined, 10), "");
  assert.equal(P.cleanPaste(null, 10), "");
});

test("typing appends, up to the maximum", () => {
  assert.equal(P.applyKey("ab", key({ text: "c" }), 10), "abc");
  assert.equal(P.applyKey("abc", key({ text: "d" }), 3), "abc");
  assert.equal(P.applyKey("ab", key({ text: "cdef" }), 4), "abcd");
});

test("Backspace removes one character; with Ctrl it clears", () => {
  assert.equal(P.applyKey("abc", key({ key: "backspace" }), 10), "ab");
  assert.equal(P.applyKey("", key({ key: "backspace" }), 10), "");
  assert.equal(P.applyKey("abc", key({ key: "backspace", ctrl: true }), 10), "");
});

test("Ctrl+U clears; other Ctrl, Alt or Meta combinations are not taken", () => {
  assert.equal(P.applyKey("abc", key({ key: "u", ctrl: true, ctrlOnly: true }), 10), "");
  assert.equal(P.applyKey("abc", key({ key: "u", ctrl: true, ctrlOnly: false, text: "u" }), 10), null);
  assert.equal(P.applyKey("abc", key({ key: "other", ctrl: true, text: "c" }), 10), null);
});

test("keys that type nothing, or a control character, are not taken", () => {
  assert.equal(P.applyKey("abc", key({ text: "" }), 10), null);
  assert.equal(P.applyKey("abc", key({ text: "\t" }), 10), null);
  assert.equal(P.applyKey("abc", key({ text: "\u007f" }), 10), null);
});
