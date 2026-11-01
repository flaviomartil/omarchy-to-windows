// How the Dock asks Hyprland for things (docs/hyprland-notes.md has the facts
// about the dispatch API). No Quickshell or QML imports, so the same file
// loads as a JS import inside the shell and via `require` under Node, where
// the tests check the text and run `bash -n` over every script.
//
// Every function returns the argv to run (`["bash", "-lc", script, "bash",
// arg]`), or null when given an address or id it cannot use, and Service.qml only runs it.
// An address is passed as an argument, never spliced into the script.

// HyprlandToplevel.address comes back as bare hex ("56538020a4f0"), unlike
// hyprctl's own "0x"-prefixed address strings: normalize before handing it to
// a dispatch's "address:0x.." window selector.
function normalizedAddress(address) {
  if (typeof address !== "string") return null;
  var hex = address.indexOf("0x") === 0 ? address.slice(2) : address;
  return /^[0-9a-fA-F]+$/.test(hex) ? "0x" + hex : null;
}

function argv(script, arg) {
  return arg === undefined ? ["bash", "-lc", script, "bash"] : ["bash", "-lc", script, "bash", arg];
}

// Focusing a floating Window doesn't raise it: one under another floating
// Window is focused but stays hidden. So a click raises a floating Window
// after focusing it. A shell function: `raise ADDRESS`. Tiled Windows are
// left alone.
var RAISE = "raise() { hyprctl -j clients | jq -e --arg a \"$1\" '.[] | select(.address == $a and .floating)' >/dev/null "
  + "&& hyprctl dispatch \"hl.dsp.window.alter_zorder({ mode = \\\"top\\\", window = \\\"address:$1\\\" })\" >/dev/null; }; ";

// Omarchy's window mode minimizes a Window by moving it to the special
// workspace "special:minimized", where focusing it does not bring it back. A
// shell function: `restore ADDRESS` moves such a Window to the workspace in
// front of the user, without animating it in, and does nothing for any other.
var RESTORE = "restore() { "
  + "hyprctl -j clients | jq -e --arg a \"$1\" '.[] | select(.address == $a and .workspace.name == \"special:minimized\")' >/dev/null || return 0; "
  + "ws=$(hyprctl -j monitors | jq -r 'first(.[] | select(.focused) | .activeWorkspace.id) // empty'); "
  + "[ \"${ws:-0}\" -ge 1 ] 2>/dev/null || return 0; "
  + "hyprctl dispatch \"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"1\\\", window = \\\"address:$1\\\" })\" >/dev/null; "
  + "hyprctl dispatch \"hl.dsp.window.move({ workspace = \\\"$ws\\\", window = \\\"address:$1\\\" })\" >/dev/null; "
  + "(sleep 0.4; hyprctl dispatch \"hl.dsp.window.set_prop({ prop = \\\"no_anim\\\", value = \\\"unset\\\", window = \\\"address:$1\\\" })\" >/dev/null) & "
  + "}; ";

// WORKAROUND, may need revisiting if Omarchy fixes it. A floating Window can be
// left outside every monitor (seen: two Edge web-app Windows at x=362 on a
// monitor that starts at x=1920, probably left on a monitor that was then
// unplugged or switched off), so focusing it from the Dock shows nothing. A shell function:
// `rescue ADDRESS` centers a floating Window that has less than 64x32 px on
// any monitor, and does nothing for any other (docs/hyprland-notes.md "Windows
// outside every monitor"). Positions are in layout pixels, so a monitor is its
// width and height over its scale.
var RESCUE = "rescue() { "
  + "lost=$(jq -s --arg a \"$1\" '"
  + ".[0] as $c | .[1] as $m | first($c[] | select(.address == $a and .floating)) as $w | "
  + "if $w == null then false else "
  + "[$m[] | ((.width / .scale) as $mw | (.height / .scale) as $mh | "
  + "([$w.at[0] + $w.size[0], .x + $mw] | min) - ([$w.at[0], .x] | max) >= 64 and "
  + "([$w.at[1] + $w.size[1], .y + $mh] | min) - ([$w.at[1], .y] | max) >= 32)] | any | not end' <(hyprctl -j clients) <(hyprctl -j monitors)) || return 0; "
  + "[ \"$lost\" = true ] && hyprctl dispatch \"hl.dsp.window.center({ window = \\\"address:$1\\\" })\" >/dev/null; "
  + "}; ";

// Focusing can warp the pointer: toggle cursor:no_warps around a dispatch and
// put the old value back.
var NO_WARPS = "orig=false; hyprctl -j getoption cursor:no_warps | grep -q '\"bool\": true' && orig=true; "
  + "hyprctl eval 'hl.config({ cursor = { no_warps = true } })' >/dev/null; ";
var WARPS_BACK = "hyprctl eval \"hl.config({ cursor = { no_warps = $orig } })\" >/dev/null";

// Peek's saved state (the focused Window, each monitor's workspace, the
// fullscreen Windows) and the lock that keeps its scripts from overlapping.
var PEEK_LOCK = "exec 9>\"${XDG_RUNTIME_DIR:-/tmp}/startbar-peek.lock\"; flock 9\n";
var PEEK_STATE = "\"${XDG_RUNTIME_DIR:-/tmp}/startbar-peek\"";

// Put back what an earlier peek changed, from the saved state in $rest: any
// Window that was maximized or full screen, then each monitor's workspace.
var PEEK_UNDO = "undo() {\n"
  + "  echo \"$rest\" | while read -r kind a b; do\n"
  + "    [ \"$kind\" = f ] || continue\n"
  + "    cur=$(hyprctl -j clients | jq -r --arg a \"$a\" '.[] | select(.address == $a) | .fullscreen')\n"
  + "    [ \"$cur\" = 0 ] || continue\n"
  + "    mode=maximized; [ \"$b\" = 2 ] && mode=fullscreen\n"
  + "    hyprctl dispatch \"hl.dsp.window.fullscreen({ mode = \\\"$mode\\\", action = \\\"set\\\", window = \\\"address:$a\\\" })\" >/dev/null\n"
  + "  done\n"
  + "  echo \"$rest\" | while read -r kind name ws; do\n"
  + "    [ \"$kind\" = m ] || continue\n"
  + "    cur=$(hyprctl -j monitors | jq -r --arg n \"$name\" '.[] | select(.name == $n) | .activeWorkspace.id')\n"
  + "    if [ \"$cur\" != \"$ws\" ]; then\n"
  + "      hyprctl dispatch \"hl.dsp.focus({ monitor = \\\"$name\\\" })\" >/dev/null\n"
  + "      hyprctl dispatch \"hl.dsp.focus({ workspace = \\\"$ws\\\" })\" >/dev/null\n"
  + "    fi\n"
  + "  done\n"
  + "}\n";

// A click on a Dock Item: focus the Window and raise it if floating. The
// pointer stays where it is.
function focusWindow(address) {
  var normalized = normalizedAddress(address);
  if (!normalized) return null;
  var script = "addr=\"$1\"; "
    + NO_WARPS
    + RAISE
    + RESTORE
    + RESCUE
    + "restore \"$addr\"; "
    + "rescue \"$addr\"; "
    + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\"; "
    + "raise \"$addr\"; "
    + WARPS_BACK;
  return argv(script, normalized);
}

// The Preview opening: rescue each of its Windows (see RESCUE), so a Window
// outside every monitor is on screen to be captured, not a blank thumbnail.
// Null when there is none to rescue.
function rescueWindows(addresses) {
  var list = (addresses || []).map(normalizedAddress).filter(Boolean);
  if (list.length === 0) return null;
  return ["bash", "-lc", RESCUE + "for a in \"$@\"; do rescue \"$a\"; done", "bash"].concat(list);
}

// A click on a hover Preview can also bring the pointer along
// (previewWarpPointer): after focusing, move it to the middle of the Window,
// read from `hyprctl -j clients`, which also covers a Window on another
// workspace or monitor once focus has switched to it.
function focusWindowAndWarp(address) {
  var normalized = normalizedAddress(address);
  if (!normalized) return null;
  var script = "addr=\"$1\"; "
    + RAISE
    + RESTORE
    + RESCUE
    + "restore \"$addr\"; "
    + "rescue \"$addr\"; "
    + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\" >/dev/null; "
    + "raise \"$addr\"; "
    + "sleep 0.1; "
    + "pos=$(hyprctl -j clients | jq -r --arg a \"$addr\" '.[] | select(.address == $a) | \"\\(.at[0] + (.size[0] / 2) | floor) \\(.at[1] + (.size[1] / 2) | floor)\"'); "
    + "[ -n \"$pos\" ] && hyprctl dispatch \"hl.dsp.cursor.move({ x = ${pos% *}, y = ${pos#* } })\" >/dev/null";
  return argv(script, normalized);
}

function closeWindow(address) {
  var normalized = normalizedAddress(address);
  if (!normalized) return null;
  return argv("hyprctl dispatch \"hl.dsp.window.close({ window = \\\"address:$1\\\" })\"", normalized);
}

function minimizeWindow(address) {
  var normalized = normalizedAddress(address);
  if (!normalized) return null;
  return argv('hyprctl dispatch "hl.dsp.window.move({ workspace = \\"special:minimized\\", follow = false, window = \\"address:$1\\" })"', normalized);
}

// The dispatch behind each Window-state row of the context menu. The ids and
// labels are DockModel.windowActions'; a test checks every id has one here.
var WINDOW_ACTIONS = {
  maximize: function (target) { return "hl.dsp.window.fullscreen({ mode = \"maximized\", " + target + " })"; },
  fullscreen: function (target) { return "hl.dsp.window.fullscreen({ mode = \"fullscreen\", " + target + " })"; },
  float: function (target) { return "hl.dsp.window.float({ action = \"toggle\", " + target + " })"; },
  center: function (target) { return "hl.dsp.window.center({ " + target + " })"; },
  pin: function (target) { return "hl.dsp.window.pin({ " + target + " })"; },
  scratchpad: function (target) { return "hl.dsp.window.move({ workspace = \"special:scratchpad\", follow = false, " + target + " })"; },
};

// One dispatch aimed at the Window by address, whether or not it is the
// focused one. The dispatch is passed as an argument, so nothing is escaped.
function windowAction(id, address) {
  var normalized = normalizedAddress(address);
  if (!normalized) return null;
  var make = Object.prototype.hasOwnProperty.call(WINDOW_ACTIONS, id) ? WINDOW_ACTIONS[id] : null;
  if (!make) return null;
  return argv("hyprctl dispatch \"$1\"", make("window = \"address:" + normalized + "\""));
}

// Peek: hovering a Preview thumbnail focuses its Window to show it. The first
// peek saves the original state; later ones undo the previous peek first,
// keeping that saved state.
function peekWindow(address) {
  var normalized = normalizedAddress(address);
  if (!normalized) return null;
  var script = PEEK_LOCK
    + PEEK_UNDO
    + "addr=\"$1\"; state=" + PEEK_STATE + "\n"
    + NO_WARPS
    + "if [ -f \"$state\" ]; then\n"
    + "  # Moving on from an earlier peek: put its changes back first, keeping the\n"
    + "  # saved original state, so only this window's peek is in effect.\n"
    + "  rest=$(tail -n +2 \"$state\")\n"
    + "  undo\n"
    + "else\n"
    + "  {\n"
    + "    hyprctl -j activewindow | jq -r '.address // \"\"'\n"
    + "    hyprctl -j monitors | jq -r '.[] | \"m \\(.name) \\(.activeWorkspace.id)\"'\n"
    + "    hyprctl -j clients | jq -r '.[] | select(.fullscreen != 0) | \"f \\(.address) \\(.fullscreen)\"'\n"
    + "  } > \"$state\"\n"
    + "fi\n"
    + "hyprctl -j clients | jq -r --arg a \"$addr\" '. as $c | ($c[] | select(.address == $a) | .workspace.id) as $w | $c[] | select(.workspace.id == $w and .fullscreen != 0 and .address != $a) | \"\\(.address) \\(.fullscreen)\"' | while read -r other fs; do\n"
    + "  mode=maximized; [ \"$fs\" = 2 ] && mode=fullscreen\n"
    + "  hyprctl dispatch \"hl.dsp.window.fullscreen({ mode = \\\"$mode\\\", action = \\\"unset\\\", window = \\\"address:$other\\\" })\" >/dev/null\n"
    + "done\n"
    + RAISE
    + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$addr\\\" })\" >/dev/null\n"
    + "raise \"$addr\"\n"
    + WARPS_BACK;
  return argv(script, normalized);
}

// Put everything a peek changed back, then forget the saved state.
function peekRestore() {
  var script = PEEK_LOCK
    + PEEK_UNDO
    + "state=" + PEEK_STATE + "; [ -f \"$state\" ] || exit 0\n"
    + "prev=$(head -n1 \"$state\"); rest=$(tail -n +2 \"$state\"); rm -f \"$state\"\n"
    + NO_WARPS
    + "undo\n"
    + "[ -n \"$prev\" ] && hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$prev\\\" })\" >/dev/null\n"
    + WARPS_BACK;
  return argv(script);
}

// A click picked the peeked Window: keep how it looks and drop the saved state.
function peekCommit() {
  return argv(PEEK_LOCK.replace("\n", "; ") + "rm -f " + PEEK_STATE);
}

// With newWindowWorkspace on: a Window that opens tiled beside other Windows
// moves to the lowest-numbered workspace with no Window on it, which is shown,
// and is maximized or full screen there as the mode says ("normal" leaves it as it is). A floating, full screen or special-workspace Window
// is left alone (dialogs, popups, Omarchy's minimized Windows), except that a
// Window Omarchy's floating workspace mode floated (tag omarchy-mode-floated)
// counts as tiled, since on such a workspace every Window floats. A Window
// that is already alone only gets the mode. The lock keeps Windows opening
// together (a restored session) from picking the same workspace.
function openOnOwnWorkspace(address, mode) {
  var normalized = normalizedAddress(address);
  if (!normalized || ["normal", "maximized", "fullscreen"].indexOf(mode) < 0) return null;
  var script = [
    "addr=\"$1\"",
    "exec 9>\"${XDG_RUNTIME_DIR:-/tmp}/startbar-newws.lock\"; flock 9",
    "sleep 0.15",
    "clients=$(hyprctl -j clients)",
    "win=$(echo \"$clients\" | jq -c --arg a \"$addr\" 'first(.[] | select(.address == $a)) // empty')",
    "[ -n \"$win\" ] || exit 0",
    "echo \"$win\" | jq -e '(.floating and ((.tags // []) | index(\"omarchy-mode-floated\") | not)) or .fullscreen != 0 or .workspace.id < 1' >/dev/null && exit 0",
    "here=$(echo \"$win\" | jq '.workspace.id')",
    "others=$(echo \"$clients\" | jq --arg a \"$addr\" --argjson w \"$here\" '[.[] | select(.workspace.id == $w and .address != $a)] | length')",
    "if [ \"$others\" -gt 0 ]; then",
    "  used=$(echo \"$clients\" | jq -c --arg a \"$addr\" '[.[] | select(.workspace.id > 0 and .address != $a) | .workspace.id] | unique')",
    "  ws=$(jq -n --argjson u \"$used\" 'first(range(1; 1000) | select(. as $i | $u | index($i) | not))')",
    "  hyprctl dispatch \"hl.dsp.window.move({ workspace = \\\"$ws\\\", window = \\\"address:$addr\\\" })\" >/dev/null",
    "fi",
    "mode=" + mode,
    "[ \"$mode\" = normal ] || hyprctl dispatch \"hl.dsp.window.fullscreen({ mode = \\\"$mode\\\", action = \\\"set\\\", window = \\\"address:$addr\\\" })\" >/dev/null",
  ].join("\n");
  return argv(script, normalized);
}

// Omarchy's Glassy look blurs what is behind a see-through surface, but only
// for the layer surfaces its own rules name. This names ours (the Dock and
// Start menu, and the settings window) so a glassy StartBar is blurred the
// same way. It is inert while Hyprland's blur is off. Named, so running it
// again replaces the rule; a `hyprctl reload` drops it, so it is run again then.
function glassRule() {
  return argv("hyprctl eval 'hl.layer_rule({ name = \"startbar-glass\", match = { namespace = \"^omarchy-startbar\" }, "
    + "blur = true, ignore_alpha = 0.3 })' >/dev/null");
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    normalizedAddress: normalizedAddress,
    focusWindow: focusWindow,
    rescueWindows: rescueWindows,
    focusWindowAndWarp: focusWindowAndWarp,
    closeWindow: closeWindow,
    minimizeWindow: minimizeWindow,
    windowAction: windowAction,
    windowActionIds: Object.keys(WINDOW_ACTIONS),
    peekWindow: peekWindow,
    peekRestore: peekRestore,
    peekCommit: peekCommit,
    openOnOwnWorkspace: openOnOwnWorkspace,
    glassRule: glassRule,
  };
}
