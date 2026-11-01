const test = require("node:test");
const assert = require("node:assert/strict");
const { parseFullName } = require("../StartMenu.js");

test("parseFullName takes the account's real name, else falls back", () => {
  assert.equal(parseFullName("bernard:x:1000:1000:Bernard Maltais,,,:/home/bernard:/bin/bash", "Bernard"), "Bernard Maltais");
  assert.equal(parseFullName("bernard:x:1000:1000::/home/bernard:/bin/bash", "Bernard"), "Bernard");
  assert.equal(parseFullName("bernard:x:1000:1000:  :/home/bernard:/bin/bash", "Bernard"), "Bernard");
  assert.equal(parseFullName("", "Bernard"), "Bernard");
  assert.equal(parseFullName(null, "Bernard"), "Bernard");
  assert.equal(parseFullName("a:x:1:1:Ann Lee:/home/a:/bin/sh\n", "a"), "Ann Lee");
});
