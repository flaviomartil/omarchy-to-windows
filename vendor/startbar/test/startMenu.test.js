const test = require("node:test");
const assert = require("node:assert/strict");
const { filterApps } = require("../StartMenu.js");

const apps = [
  { id: "org.gnome.Calculator", name: "Calculator", genericName: "", keywords: ["math"] },
  { id: "firefox", name: "Firefox", genericName: "Web Browser", keywords: ["internet"] },
  { id: "alacritty", name: "Alacritty", genericName: "Terminal", keywords: [] },
  { id: "hidden", name: "Secret", noDisplay: true },
  { id: "chromium", name: "Chromium", genericName: "Web Browser", keywords: [] },
];

const ids = (list) => list.map((a) => a.id);

test("an empty query lists every displayable app, alphabetically by name", () => {
  assert.deepEqual(ids(filterApps(apps, "")), ["alacritty", "org.gnome.Calculator", "chromium", "firefox"]);
  assert.deepEqual(ids(filterApps(apps, "   ")), ids(filterApps(apps, "")));
});

test("name prefix matches rank first, then name substrings, then generic name/keywords/id; ties alphabetical", () => {
  assert.deepEqual(ids(filterApps(apps, "c")), ["org.gnome.Calculator", "chromium", "alacritty"]);
  assert.deepEqual(ids(filterApps(apps, "web")), ["chromium", "firefox"]);
});

test("matching is case-insensitive and also checks keywords and the id", () => {
  assert.deepEqual(ids(filterApps(apps, "FIRE")), ["firefox"]);
  assert.deepEqual(ids(filterApps(apps, "math")), ["org.gnome.Calculator"]);
  assert.deepEqual(ids(filterApps(apps, "internet")), ["firefox"]);
});

test("apps with noDisplay never appear, and no match gives an empty list", () => {
  assert.deepEqual(ids(filterApps(apps, "secret")), []);
  assert.deepEqual(ids(filterApps(apps, "zzz")), []);
  assert.deepEqual(filterApps(null, "x"), []);
});


const { effectivePlaces } = require("../StartMenu.js");

const userDirs = [
  "# comment",
  'XDG_DESKTOP_DIR="$HOME/"',
  'XDG_DOWNLOAD_DIR="$HOME/Downloads"',
  'XDG_DOCUMENTS_DIR="$HOME/Documents"',
  'XDG_MUSIC_DIR="$HOME/Music"',
  'XDG_PICTURES_DIR="$HOME/Pictures"',
  'XDG_VIDEOS_DIR="$HOME/Videos"',
  'XDG_PROJECTS_DIR="$HOME/Projects"',
].join("\n");

test("effectivePlaces starts with Home, then the user's XDG folders, skipping any that are Home itself", () => {
  const places = effectivePlaces(null, userDirs, "/home/u");
  assert.deepEqual(places.map((p) => p.label), ["Home", "Documents", "Downloads", "Pictures", "Music", "Videos"]);
  assert.equal(places[0].path, "/home/u");
  assert.equal(places[2].path, "/home/u/Downloads");
  assert.equal(places[2].icon, "folder-download");
});

test("effectivePlaces falls back to conventional names when user-dirs.dirs is unreadable", () => {
  const places = effectivePlaces(null, "", "/home/u");
  assert.deepEqual(places.map((p) => p.path), [
    "/home/u", "/home/u/Documents", "/home/u/Downloads", "/home/u/Pictures", "/home/u/Music", "/home/u/Videos",
  ]);
});

test("a startPlaces list replaces the defaults; ~ expands, labels come from the folder name", () => {
  const places = effectivePlaces(["~/Projects", "/mnt/data", "", 5, "~/Projects"], userDirs, "/home/u");
  assert.deepEqual(places.map((p) => [p.label, p.path]), [
    ["Projects", "/home/u/Projects"],
    ["data", "/mnt/data"],
  ]);
  assert.equal(places[0].icon, "folder");
});

test("an empty startPlaces list hides the Places column", () => {
  assert.deepEqual(effectivePlaces([], userDirs, "/home/u"), []);
});
