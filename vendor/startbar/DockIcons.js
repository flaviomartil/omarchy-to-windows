// Finding an App's icon file when Qt cannot (docs/SPEC.md "What the Dock
// shows"). No Quickshell or QML imports, so the same file loads as a JS import
// inside the shell and via `require` under Node, where the tests check the
// text and run `bash -n` over the script.
//
// Quickshell.iconPath(name, true) remembers a miss for the life of the shell:
// an icon installed after its App's first lookup (a package installed while
// the shell runs) stays "" until the shell restarts, and QML cannot clear the
// cache. So on a miss the Dock looks for the file itself: searchCommand builds
// the command that lists candidates, pickBest chooses one, and Service.qml
// only runs the command and hands the path to the Image (IconResolver.qml,
// shared by the Dock and the Start menu).

// An Icon= value that is not a plain theme name (a path, or glob characters)
// is left to Qt: it is passed to `find -name`.
var NAME = /^[A-Za-z0-9._+-]+$/;

// A package can finish installing a few seconds after its Window opens, so a
// search that finds nothing is tried again, a few times.
var MAX_TRIES = 3;
var RETRY_MS = 10000;

var SCRIPT = "name=$1; dirs=(); "
  + "IFS=: read -ra bases <<< \"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\"; "
  + "for b in \"${bases[@]}\"; do "
  + "[ -d \"$b/icons\" ] && dirs+=(\"$b/icons\"); [ -d \"$b/pixmaps\" ] && dirs+=(\"$b/pixmaps\"); done; "
  + "[ ${#dirs[@]} -gt 0 ] && timeout 5 find -L \"${dirs[@]}\" -type f \\( -name \"$name.png\" -o -name \"$name.svg\" \\) 2>/dev/null | head -n 200; true";

// At most 200 lines, and the search gives up after 5 seconds.
// The argv that prints every file named `name`.png or .svg in the icon
// directories, one per line; null for a name it cannot search for.
function searchCommand(name) {
  if (typeof name !== "string" || !NAME.test(name)) return null;
  return ["bash", "-lc", SCRIPT, "bash", name];
}

// The best of the listed files: a scalable one if there is one, else the
// largest size (".../128x128/apps/x.png"), else the first. "" for none.
function pickBest(output) {
  var lines = String(output || "").split("\n").filter(function (line) { return line.length > 0; });
  var best = "";
  var bestScore = -1;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var size = /\/(\d+)x\d+\//.exec(line);
    var score = /\.svg$/.test(line) || line.indexOf("/scalable/") >= 0 ? 100000 : (size ? Number(size[1]) : 1);
    if (score > bestScore) { best = line; bestScore = score; }
  }
  return best;
}

// Whether a name that is still missing should be searched for now: never
// searched, or searched fewer than MAX_TRIES times and the last search was at
// least RETRY_MS ago. (The Dock asks again on every refresh, so the spacing
// has to be in time, not just in a count.)
function shouldSearch(tries, lastMs, nowMs) {
  if (!tries) return true;
  return tries < MAX_TRIES && nowMs - lastMs >= RETRY_MS;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MAX_TRIES: MAX_TRIES,
    RETRY_MS: RETRY_MS,
    searchCommand: searchCommand,
    pickBest: pickBest,
    shouldSearch: shouldSearch,
  };
}
