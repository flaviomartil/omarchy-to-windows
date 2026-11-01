const test = require("node:test");
const assert = require("node:assert/strict");
const {
  settingsSchema,
  effectiveView,
  applyIntent,
  barMenuRows,
  fieldEnabled,
  searchSettings,
} = require("../DockConfig.js");

const settingsValues = (entry) => effectiveView(entry).values;
const effectiveTaskbar = (entry) => effectiveView(entry).taskbar;

const fields = () => settingsSchema().flatMap((g) => g.fields);
const TYPES = ["bool", "choice", "int", "slider", "text", "list"];

test("every field has a unique key, a label and a known widget type", () => {
  const keys = fields().map((f) => f.key);
  assert.equal(new Set(keys).size, keys.length);
  for (const f of fields()) {
    assert.ok(f.label, f.key);
    assert.ok(TYPES.includes(f.type), `${f.key}: ${f.type}`);
    if (f.type === "choice") assert.ok(f.options.length >= 2, f.key);
    if (f.type === "int" || f.type === "slider") {
      assert.ok(f.min < f.max && f.step > 0, f.key);
    }
  }
});

test("the schema covers every setting the config module understands, and nothing else", () => {
  const known = new Set([
    ...Object.keys(effectiveView(null).settings),
    ...Object.keys(effectiveView(null).taskbar),
    "startPlaces",
  ]);
  const schemaKeys = new Set(fields().map((f) => f.key));
  assert.deepEqual([...schemaKeys].sort(), [...known].sort());
});

test("settingsValues gives every field its effective value, defaults when unset", () => {
  const values = settingsValues(null);
  for (const f of fields()) assert.ok(f.key in values, f.key);
  assert.equal("style" in values, false);
  assert.equal(values.iconSize, 48);
  assert.equal(values.startPlaces, null);
  assert.equal(values.showWorkspaceBadge, false);
});

test("settingsValues reflects the entry, including a custom startPlaces list", () => {
  const values = settingsValues({ alignment: "left", iconSize: 64, startPlaces: ["~/a", "~/b"] });
  assert.equal(values.alignment, "left");
  assert.equal(values.iconSize, 64);
  assert.deepEqual(values.startPlaces, ["~/a", "~/b"]);
});

test("a choice field's options are exactly the values the config accepts", () => {
  for (const f of fields().filter((x) => x.type === "choice")) {
    for (const o of f.options) {
      const entry = { [f.key]: o.value };
      assert.equal(settingsValues(entry)[f.key], o.value, `${f.key}=${o.value}`);
    }
  }
});

test("int and slider ranges sit inside what the config accepts as usable", () => {
  for (const f of fields().filter((x) => x.type === "int" || x.type === "slider")) {
    for (const v of [f.min, f.max]) {
      const got = settingsValues({ [f.key]: v })[f.key];
      assert.equal(got, v, `${f.key}=${v}`);
    }
  }
});

test("setSettings removes a key when its patched value is undefined or null", () => {
  assert.deepEqual(applyIntent({ a: 1, b: 2 }, { type: "setSettings", patch: { a: undefined } }), { b: 2 });
  assert.deepEqual(applyIntent({ a: 1, b: 2 }, { type: "setSettings", patch: { b: null } }), { a: 1 });
  assert.deepEqual(applyIntent({ a: 1 }, { type: "setSettings", patch: { a: 0 } }), { a: 0 });
});

test("the quick menu ends with a Settings... row that opens the settings window", () => {
  const rows = barMenuRows(effectiveTaskbar({}));
  const last = rows[rows.length - 1];
  assert.equal(last.label, "Settings\u2026");
  assert.equal(last.action, "settings");
});

test("a field with enabledWhen is enabled only while its other setting has the stated value", () => {
  const field = (key) => fields().find((f) => f.key === key);
  assert.equal(fieldEnabled(field("revealDelayMs"), settingsValues({ autoHide: true })), true);
  assert.equal(fieldEnabled(field("revealDelayMs"), settingsValues({})), false);
  assert.equal(fieldEnabled(field("opacity"), settingsValues({})), true);
  assert.equal(fieldEnabled(field("opacity"), settingsValues({ transparent: true })), false);
  assert.equal(fieldEnabled(field("previewPeek"), settingsValues({ showPreviews: false })), false);
  assert.equal(fieldEnabled(field("clock"), settingsValues({})), true);
});

test("every enabledWhen names another field, never itself", () => {
  const keys = new Set(fields().map((f) => f.key));
  for (const f of fields().filter((x) => x.enabledWhen)) {
    assert.ok(keys.has(f.enabledWhen.key), f.key);
    assert.notEqual(f.enabledWhen.key, f.key);
    assert.equal(typeof f.enabledWhen.is, "boolean", f.key);
  }
});

test("every row the menu can click is enabled or says nothing about it, never falsy by omission", () => {
  const rows = barMenuRows(effectiveTaskbar({}));
  const clickable = rows.filter((r) => !r.children).concat(rows.flatMap((r) => r.children || []));
  for (const r of clickable) assert.equal(r.enabled !== false, true, r.label);
});

test("search keeps the fields whose label, hint or page match every word, in any case", () => {
  const keysOf = (query) => searchSettings(settingsSchema(), query).flatMap((g) => g.fields.map((f) => f.key));

  assert.deepEqual(keysOf("hide delay"), ["hideDelayMs"]);
  assert.deepEqual(keysOf("DELAY HIDE"), ["hideDelayMs"]);
  assert.ok(keysOf("clock").includes("showClock"));
  // a hint is searched too: "thumbnail" only appears in a hint
  assert.ok(keysOf("thumbnail").includes("previewPeek"));
  // a choice's option labels are searched too: "maximized" only labels an option
  assert.ok(keysOf("maximized").includes("newWindowWorkspace"));
  // a page title matches all its fields
  const start = searchSettings(settingsSchema(), "start menu");
  assert.deepEqual(start.map((g) => g.title), ["Start menu"]);
  assert.equal(start[0].fields.length, settingsSchema().find((g) => g.title === "Start menu").fields.length);
});

test("search groups results by page, and a blank or unmatched query gives none", () => {
  assert.deepEqual(searchSettings(settingsSchema(), ""), []);
  assert.deepEqual(searchSettings(settingsSchema(), "   "), []);
  assert.deepEqual(searchSettings(settingsSchema(), null), []);
  assert.deepEqual(searchSettings(settingsSchema(), "zzzz"), []);
  const pages = searchSettings(settingsSchema(), "preview").map((g) => g.title);
  assert.deepEqual(pages, ["Windows"]);
  assert.ok(searchSettings(settingsSchema(), "icon").map((g) => g.title).length >= 2);
});
