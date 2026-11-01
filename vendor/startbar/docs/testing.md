# Testing StartBar

How a change gets checked, from the cheapest check to trying it in a live shell. Written so a person or an agent can pick it up cold, and so it can be improved: the last sections say how it works inside and what went wrong on the way.

The test session, the tour recorder and the scripts around them come from StartDrive and StartAppImage, which share them (see [Shared with the other Start apps](#shared-with-the-other-start-apps)). What is StartBar's own is the guard that keeps a click in the session from reaching your machine, the commands for a Dock that is a service and not a window, and the tours.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the rules, the manifest, the QML and the scripts are not broken | `npm run check` (runs on every commit) | no |
| run only the rules | `npm test` | no |
| see the plugin run, hover it, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse and keyboard, with a home of its own |
| check a change loads quietly and looks right in each colour scheme | `npm run smoke` | no: it runs in the same session |
| watch that session | `scripts/dev watch` | a view-only window |
| retake the README's screenshots | `scripts/screenshots.sh` | no |
| record the README's animations | `scripts/hero.sh`, `scripts/clips.sh` ([recording-tours.md](recording-tours.md)) | no |
| look over a recording | `scripts/sheet` | no |
| try it on your own shell | `scripts/reload`, `scripts/pointer.sh`, `scripts/try-setting.sh` | yes: restarts your shell, moves your pointer, edits your `shell.json` for a moment |

**The rule: test in `scripts/dev`, not on the real desktop.** A restart of the real shell makes the bar blink and puts the Dock's menus away; a click or key sent to it moves your pointer and types into your windows; the Dock acts on your real windows. The test session has none of that. Use `reload`, `pointer.sh` and `try-setting.sh` only when the person asks to see it on their real shell, or for what the session cannot do (a real mouse drag, a second monitor, the user's real Hyprland configuration).

## 1. Checks: `npm run check`

One command, no running shell needed. The pre-commit hook runs it (`git config core.hooksPath .githooks`). What it runs, and the Node tests, are described in [CONTRIBUTING.md](../CONTRIBUTING.md#checks). Two parts are about the session:

- `scripts/lint-sh.sh`: `bash -n` and shellcheck over every script (the rules are in `.shellcheckrc`, with the reason for each one disabled).
- `scripts/lint-rules.sh`: project rules no linter knows, each one a mistake that cost a session: a background launch (`setsid -f`) must redirect its own output (see section 6), and a tour must not copy or link the real `shell.json`. `test/lintRules.test.js` proves each rule catches what it is for.
- `test/nestedGuard.test.js`: builds the guard (below) in a throwaway folder and checks it refuses every power command the Start menu can run, with `systemctl` and `loginctl` replaced by stand-ins that only say they were reached.

What it cannot catch: a layout that looks wrong, a click that misses, anything about the live shell. That is what the test session is for.

## 2. The test session: `scripts/dev`

A second Hyprland with its own Omarchy shell, running this checkout as the plugin, driven over its own Wayland socket. `scripts/dev --help` is the reference; this is the shape of a session:

```sh
scripts/dev up                       # 10 s. a nested desktop, out of your mouse's reach, and a window showing it live
scripts/dev run foot -a foot sleep 600     # a window for the Dock to show (a throwaway terminal; run it twice for a group)
scripts/dev startmenu                # open the Start menu there (settings opens the settings window, close closes both)
scripts/dev shot /tmp/a.png          # screenshot it, then look at the file
scripts/dev layout | jq .            # where the Dock's Items and any open menu are, in pixels of that screenshot
scripts/dev click 31 776             # click the pixel you saw (rclick for the right button, scroll PX PY N for the wheel)
scripts/dev move 78 776              # move the pointer there: the Preview opens when it rests on an Item
scripts/dev type fo                  # type into the Start menu or the settings window; key Return presses a key
scripts/dev set '{"colorScheme":"light","position":"left"}'    # change the Dock's settings; the Dock follows at once
scripts/dev errors                   # what the plugin logged, noise removed (0 = clean)
# edit a .qml file ...
scripts/dev reload                   # 5 s. restarts the nested shell only; loads uncommitted files
scripts/dev down                     # always, when done
```

Every command prints one line and exits non-zero when it did not do what it says (`dev reload FAILED ... qml-errors 2`, `dev startmenu: the window did NOT open`).

- **Pixels** are the session's screen, 1280×800 by default (`DEV_SIZE=1920x1200 scripts/dev up` for a larger one), 0,0 at the top-left, exactly as in a `dev shot`. Read the pixel off the screenshot and click it; nothing is scaled or offset. `dev layout` gives the Dock's Items and menus in the same pixels, so a script does not have to find them in a picture.
- **The Dock starts from its defaults**, plus the clock: no Pins, no Start Pins, no Placed positions. `dev set` changes that, and `dev run` gives it windows. The Items you see are the session's own windows (it has nothing else), and the Start menu lists the apps installed on the machine.
- **No commit or push is needed.** The plugin in the session is a link to this checkout, so `reload` loads what is on disk.
- **It closes itself** after `DEV_TTL` seconds (default 1800), and a stale session is cleaned up by the next `up`. End it yourself with `down`: the session holds a virtual monitor and about a dozen processes.
- **`scripts/dev env`** prints shell code that puts a script in the session's environment (`eval "$(scripts/dev env)"`): its home, its guard first on `PATH`, its compositor, so `hyprctl`, `omarchy-shell` and `foot` then act there. `scripts/screenshots.sh` runs the tours' helpers that way.

### The guard: what a click in the session cannot do

The session shares your user's systemd, your login session and your system bus. The Start menu has Lock, Sign out, Sleep, Restart and Shut down, and they run the real commands (`omarchy-system-lock`, `omarchy-system logout`, `systemctl suspend`, `omarchy-system reboot`, `omarchy-system shutdown`). A click on one inside the session would act on your machine: it would go down, or the session you are working in would end or lock. Omarchy's own `omarchy-system-lock` also kills the screensaver and locks 1Password, whichever session runs it.

So the session runs with a guard first on its `PATH` (`sandbox_guard` in `scripts/nested/session.sh`): a stand-in for each of those commands that refuses, says so, and writes the attempt to `guard.log` in the session's folder (`dev status` counts them). `omarchy-system*`, `poweroff`, `reboot`, `shutdown`, `halt`, `hyprlock` and `uwsm` are refused whatever the arguments; `systemctl` and `loginctl` are refused for the verbs that act on the machine or the login session (`poweroff`, `reboot`, `suspend`, `hibernate`, `lock-session`, `terminate-user` ...) and passed on for anything else, since the shell reads unit states.

The session is not started unless the guard works (`guard_check`): it asks a login shell, as the Start menu's `bash -lc` runs its commands, where each of those commands is, and refuses to go on if one is not the guard's. Only then does it run the five commands the menu runs, and demands all five were refused. This was tried for real, once, by clicking Sleep in the session: `guard.log` said `systemctl suspend` and nothing suspended.

To guard another command (a new row in the menu, a new tool a plugin runs), add it to `sandbox_guard` and to the test in `test/nestedGuard.test.js`. The test takes the commands from `StartMenu.overlayRows`, so a new Start menu row that the guard does not hold fails it.

### Retaking the README screenshots: `scripts/screenshots.sh`

Runs the whole thing in the session: `up`, the Dock set to the state the README shows (`scripts/tours/common.sh`: icons on the left, the theme's colours, five Pins) with terminals posing as apps for its windows, then each image in turn, each framed as before: the subject plus a 32 px margin of wallpaper, the Dock and what stands on it running on to the screen's bottom edge. `--only NAME,NAME` takes some, `--install` copies them over `screenshots/`, `--out DIR` says where they go. It finds the Items and menus with `dev layout`, so nothing is found by comparing pictures. Then `scripts/make-preview.sh` rebuilds `preview.png`, the marketplace's picture, from them.

### The smoke test: `npm run smoke`

`scripts/smoke.sh` starts the session, opens the Dock, the Start menu and the settings window in each colour scheme (`--position EDGE`, `--type` to type into the search), screenshots each, and fails if the plugin logged anything. Read the screenshots: it only knows the plugin loaded quietly. It cannot hover or drag; for a Preview or a menu, drive the session by hand (above) or run a tour.

### Watching it: `scripts/dev watch`

`up` opens it (`DEV_WATCH=0 scripts/dev up` for none; `dev watch` opens it later). It is an ordinary window (`scripts/dev-view.qml`) that shows the session five times a second. Drag it, cover it, resize it, send it to the scratchpad: your pointer is the normal arrow over it and a click does nothing, because nothing in it listens. `scripts/dev unwatch` closes it. It ends with the session.

The session's *own* window is never put on your screen. That was tried and it was wrong: see section 6.

## 3. Your real desktop: `scripts/reload`, `scripts/pointer.sh`, `scripts/try-setting.sh`

For when someone wants to see the change in their own shell, or for what a nested session cannot do.

- `scripts/reload [--check]` restarts your shell so it loads this checkout (the plugin in `~/.config/omarchy/plugins/` is a link to it, `CONTRIBUTING.md` "Development install"; the script refuses otherwise) and reports what the plugin logged: `reload ok release/1.5.0@93575aa restart 4.1s plugin-errors 0`. The bar blinks. Your windows, settings and Pins are untouched. Changes to `Service.qml` and `StartMenuView.qml` need this restart; the shell does not reload them on save.
- `scripts/pointer.sh`, `scripts/try-setting.sh` and `scripts/spare.sh` are the old tools for the real desktop: a real pointer through `ydotool`, StartBar's settings changed for one command and put back, and a spare window to try Hyprland calls on. See `docs/hyprland-notes.md`. `pointer.sh` moves your real pointer: only when asked.

## 4. Looking over a recording: `scripts/sheet`

`scripts/sheet FILE.avif|gif [--every S] [--width PX] [--cols N] [--out FILE]` makes one contact sheet image from an animation, so a whole recording can be checked at once. It knows that an AVIF holds two video streams (the still cover, then the animation) and reads the second.

## 5. How it works inside

```
scripts/dev ──► scripts/nested/session.sh ──► Hyprland (nested) ──► quickshell: the Omarchy shell + this plugin
   │                  (sandbox, guard, start, stop)    │ a window of your compositor, moved to a virtual monitor
   │                                                   │   at x = 20000, which a real pointer cannot reach
   ├─ click, move, rclick, scroll ► scripts/nested/vptr (virtual pointer) on the session's socket
   ├─ type, key ───────────► wtype (virtual keyboard), on the session's socket
   ├─ shot ────────────────► grim, on the session's socket
   ├─ layout, startmenu ... ► omarchy-shell, on the session's socket (the plugin's IPC)
   └─ errors ──────────────► the session's shell log, filtered
```

- **`scripts/nested/session.sh`** is shared with the recorder (`scripts/tour.sh`). It builds the sandbox home (Omarchy's themes copied, a `shell.json` that keeps your bar layout but only Omarchy's own widgets, with this plugin's entry holding the settings the session starts with, the plugin linked to the checkout), builds the guard, starts the nested Hyprland under its own D-Bus that starts nothing, and stops everything it started.
- **The plugin is a service.** It has no bar widget, so the session loads it without putting it on the bar (`TOUR_PLUGIN_WIDGET=0`), and its settings come from `TOUR_PLUGIN_ENTRY`, merged into its entry in the sandbox's `shell.json`.
- **Input.** `scripts/nested/vptr.c` is a tiny client of the `wlr-virtual-pointer` protocol (built on first use into the session's folder). Keys use `wtype`. Both talk to the nested compositor's socket, so nothing reaches your real seat. The virtual pointer produces real motion, so a Preview opens when it rests on an Item.
- **Your mouse and keyboard are switched off inside the session.** The host seat gives the nested compositor two devices, `wl_pointer` and `wl_keyboard`; its config disables both (`hl.device({ name = ..., enabled = false })`). The virtual devices are separate and keep working.
- **The far monitor.** `up` creates a headless monitor `DEVTEST` 20,000 px to the right and moves the window there. Sliding a mouse off the edge of your screen stops at the edge, so the window cannot be reached. `down` removes the monitor.
- **The shell starts last.** Hyprland starts the session's shell only once the window has its final size (`nested_send_away` creates a file the start waits for). Started earlier, the shell keeps reporting the window's first size as its screen's, and the Dock's `layout` then answers with pixels that are wrong by the difference.
- **The noise filter.** `errors` and `reload` count only lines that name this plugin's files (`io.github.bmaltais.startbar`) and carry a warning or error, minus known noise (layout "recursive rearrange", "Local plugin changed", qmlscanner, portal, `qt.svg`). Omarchy's own errors are not ours and are not counted.

## 6. What went wrong on the way, and the rule it left

Each of these cost a round of testing; they are why the design is what it is. Most are StartDrive's and StartAppImage's, kept here because they apply as much.

- **Never put the nested compositor's window under a real pointer.** While a pointer is over it, the nested compositor chooses the cursor image: it hid the pointer, showed a hand, and left the pointer behaving oddly after a window drag. A transparent *shield* over the window cured the input but showed a "block" cursor and stopped the window being dragged. Hence the far monitor for the session and the separate view window for watching.
- **Do not change the nested compositor's cursor options at runtime** (`hl.config({ cursor = ... })` through `hyprctl eval`): it crashed the nested Hyprland.
- **A reused socket name hid the session.** The nested compositor's socket is `wayland-N` and the number is reused, so finding "the new socket" by a name that was absent before failed after an aborted cleanup left a stale file. It is found by being created after the start, and `down` removes its own socket and instance folder.
- **`pgrep -f` matches its own shell.** Find processes by an environment marker (`procs_with` in `scripts/nested/session.sh`) or use a `[x]` bracket pattern.
- **Plugin reload does not load QML.** Only a full shell restart does. Both `scripts/reload` and `dev reload` do that restart.
- **A background process that keeps the caller's output open makes `dev up | tail` hang.** Every detached launch ends in `>/dev/null 2>&1 </dev/null`; `scripts/lint-rules.sh` fails on one that does not.
- **`DEV_WATCH=0` hides the view window.** `scripts/dev up` opens it unless that is set.
- **A shell that starts before its window has its final size reports the wrong screen** (StartBar's). `layout` put the Items 188 px left and 38 px high of where they were, and the first version of the tour clicked next to its targets. The shell now starts after the resize; see section 5.
- **A window moved off the workspace in view is still the "active window"** (StartBar's). A Peek puts the focus back to the window that had it, and if that was a window of another workspace the compositor switched there, so the film stayed on the wrong workspace for good. After posing windows on other workspaces, `settle_focus` in `scripts/tours/common.sh` switches to them and back, which clears it.
- **Right-click an Item of a Dock on the top or left edge: the menu opens and closes at once, in the session** (StartBar's, not understood). The menu's hover handler is told the pointer is inside it at a position that is the pointer's place in the *bar's* window and not in the menu's, so the menu counts it as entered and left, and closes 300 ms later. It does not happen on the bottom or right edge, and the 1.5.0 README's tour shows it working on the left edge of a real desktop, so it is the nested compositor or the virtual pointer and not the plugin. The tours right-click Items on a bottom Dock.
- **The Peek keeps its state in a file in `$XDG_RUNTIME_DIR`**, `startbar-peek` and its lock, which the session shares with your real shell (StartBar's). A Peek in the session while you hover a Preview on your real desktop can put back the wrong workspace. Do not hover Previews on your real desktop while a session peeks (the hero tour does in its first scene, and the taskbar clip throughout). Keying the file by `$HYPRLAND_INSTANCE_SIGNATURE` in `DockHyprland.js` would end it; it has not been done, because it changes what ships.
- **A recording leaves 1.5 GB in `/tmp`, and `/tmp` is memory.** The recorder takes a frame with `grim` every 15 ms, and kept them. A few runs filled it, and then everything that writes there failed, the session included (a recording that took 92 seconds took 153 and showed the wallpaper for a minute). `tour.sh` now removes its folder when it ends; `TOUR_KEEP_TMP=1` keeps it for a run that went wrong.
- **ffprobe reads one frame of an AVIF.** It shows the still cover image first; the animation is the second video stream (`-f mov -map 0:v:1`). `scripts/sheet` does this for you.

## 7. Limits, and ideas for improving it

- **Hyprland only, and a newer Hyprland than 0.56 may change the Lua API** (`hl.dsp.window.move`, `hl.device`, `hl.monitor`) that `scripts/nested/session.sh`, `scripts/dev` and `scripts/tours/common.sh` use.
- **One session at a time** (a fixed state folder and monitor name). A tour and `dev` use different monitors but would race for the nested compositor's socket: do not run both.
- **One monitor.** The Dock puts an Item for every window on every monitor and has a Dock on each; the session has one screen. A second monitor needs the real desktop.
- **The apps are the machine's.** The Start menu lists what is installed here and the tours pin five apps that must be installed (`TOUR_PINS` in `scripts/tours/common.sh`; the tour says which is missing), so the images differ from machine to machine.
- **No drag.** `vptr` can drag (the recorder uses it for windows) and `dev` has no `drag` yet: dragging an Item or a Pin on the Dock is on the manual checklist.
- **The view window is a picture, not the session**: five frames a second, so a fast animation looks choppy.
- **Right-clicking an Item on the top or left edge** (section 6).
- **Ideas:** a `dev drag`; a `dev run SCRIPT` that replays a list of steps and fails on the first miss; keying the Peek's state file by Hyprland instance.

## Shared with the other Start apps

`scripts/dev`, `scripts/dev-view.qml`, `scripts/nested/`, `scripts/tour.sh`, `scripts/tour-banner.qml`, `scripts/sheet` and the documents about them are StartDrive's and StartAppImage's, copied here (StartDrive's, the newer, is the base). They are meant to live in one shared repository eventually; until then, what StartBar changed in them is listed so that it can go upstream:

- `scripts/nested/vptr.c`: `rclick` (the right button) and `scroll X Y W H N` (the wheel). `scripts/nested/session.sh` has `nest_rclick` and `nest_scroll`; `scripts/dev` has `rclick`, `scroll`; `scripts/tour.sh` has `rclick` and `scroll`.
- `scripts/nested/session.sh`: `TOUR_PLUGIN_ENTRY` and `TOUR_PLUGIN_WIDGET` (a plugin's starting settings, and a plugin with no bar widget); `disabledPlugins` is kept from your `shell.json`; the shell starts once the window has its final size (`NEST_GO`); the guard (`sandbox_guard`, `guard_check`) in the place of `sandbox_repoint`'s demo mode.
- `scripts/tour.sh`: `tour_keys_ok` and `layer_up` (for a window that is not a layer of its own), `pressed KEY`, `rclick`, `scroll`; a failing `tour_prepare` or `tour_setup` stops the run; the run's folder is removed when it ends (`TOUR_KEEP_TMP=1` keeps it), which StartDrive's and StartAppImage's recorders do not do yet.
- `scripts/dev`: `startmenu`, `settings`, `close`, `layout`, `run`, `windows`, `set`, `env` for a service, in the place of `open`, `setup` and `settings ID`; `rclick`, `scroll`; `move` is StartDrive's.

What is StartBar's own: `scripts/tours/` (the story, the Pins, the windows that pose as apps), the guard's list of commands, `scripts/smoke.sh`, `scripts/screenshots.sh` and `scripts/reload`.

## Where the files are

| Path | What it is |
|---|---|
| `package.json` `check`, `scripts/lint-sh.sh`, `scripts/lint-rules.sh`, `scripts/qmllint-check.js`, `scripts/qmllint-baseline.txt`, `.shellcheckrc` | the checks |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook and the CI job |
| `test/*.test.js` | the Node tests (`nestedGuard`, `lintRules`, and the modules') |
| `scripts/dev`, `scripts/dev-view.qml` | the test session and its view window |
| `scripts/nested/` | session start/stop, the sandbox, the guard, the virtual pointer; shared with the recorder |
| `scripts/smoke.sh`, `scripts/screenshots.sh`, `scripts/make-preview.sh` | the smoke test, the README screenshots, the marketplace picture |
| `scripts/tour.sh`, `scripts/tours/`, `scripts/tour-banner.qml`, `scripts/hero.sh`, `scripts/clips.sh` | the recorder and the tours ([recording-tours.md](recording-tours.md)) |
| `scripts/sheet` | contact sheets |
| `scripts/reload`, `scripts/pointer.sh`, `scripts/try-setting.sh`, `scripts/spare.sh`, `scripts/hypr-events.sh` | for the real desktop |
