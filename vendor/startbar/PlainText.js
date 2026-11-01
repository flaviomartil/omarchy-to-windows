// What a plain text field does with a key or a paste (PlainField.qml draws
// and carries it out). No Quickshell or QML imports, so the same file loads
// as a JS import inside the shell and via `require` under Node for the tests.
//
// The fields are not native TextInputs: a TextInput reads the clipboard
// whenever it changes, with no size limit or deadline, which lets a hostile
// clipboard owner stall the shell. A plain field never touches the clipboard
// on its own. Ctrl+V runs pasteCommand(), which is bounded in time and size.

var MAX_PASTE_BYTES = 4096;

// The text on the clipboard, at most MAX_PASTE_BYTES of it, giving up after a
// second. `timeout` ends a provider that never finishes; `head -c` closes the
// pipe, and so stops wl-paste, once it has enough.
function pasteCommand() {
  return ["bash", "-lc",
    "timeout 1 wl-paste --no-newline --type text/plain 2>/dev/null | head -c " + MAX_PASTE_BYTES + "; true"];
}

// Pasted text made fit for one line: line breaks and tabs become spaces,
// other control characters go, and it is cut to `room` characters.
function cleanPaste(raw, room) {
  var text = String(raw === undefined || raw === null ? "" : raw)
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, "");
  return text.slice(0, Math.max(0, room));
}

// A key's effect on the text: the new text, or null when the field does not
// take the key. `k` is { key, ctrl, text }, where key is "backspace", "u" (a
// letter, lower case) or "other", ctrl is any of Ctrl/Alt/Meta held, and text
// is what the key types.
function applyKey(text, k, maxLength) {
  if (k.key === "backspace") return k.ctrl ? "" : text.slice(0, -1);
  if (k.ctrl) return k.key === "u" && k.ctrlOnly ? "" : null;
  var typed = String(k.text || "");
  if (typed.length === 0) return null;
  var code = typed.charCodeAt(0);
  if (code < 32 || code === 127) return null;
  if (text.length >= maxLength) return text;
  return (text + typed).slice(0, maxLength);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MAX_PASTE_BYTES: MAX_PASTE_BYTES,
    pasteCommand: pasteCommand,
    cleanPaste: cleanPaste,
    applyKey: applyKey,
  };
}
