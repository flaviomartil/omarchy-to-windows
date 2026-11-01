# Recording tours

How to record a short animation that shows StartBar being used, with `scripts/tour.sh`. It makes `screenshots/hero.avif`, the tour at the top of the README, and the clips further down it. The recorder is **not specific to StartBar**: it is StartDrive's, and every Start app uses it with a *tour file* of its own that says what to do. This document is StartDrive's, with what is different for a Dock.

- [Run the tours](#run-the-tours)
- [What you need](#what-you-need)
- [What happens when you run it](#what-happens-when-you-run-it)
- [Writing a tour](#writing-a-tour)
- [Clips](#clips)
- [Reference](#reference)
- [Troubleshooting](#troubleshooting)
- [Human-like input](#human-like-input)
- [Reading time](#reading-time)

## Run the tours

```sh
scripts/hero.sh              # records the hero, leaves the result in /tmp/hero.avif for a look
scripts/hero.sh --install    # records it and copies it to screenshots/hero.avif
scripts/clips.sh             # records the five clips and installs them in screenshots/ (or: scripts/clips.sh start-menu settings)
scripts/tour.sh scripts/tours/start-menu-clip.sh      # one tour, to look at it first (/tmp/start-menu-clip.avif)
```

`scripts/hero.sh` is a shortcut for `scripts/tour.sh scripts/tours/hero.sh`. It takes about three minutes, of which the tour itself is a minute and a half. A red strip appears along the top of your screen with a **Cancel recording** button, and a view-only window below it shows the recording as it happens. **Your mouse and keyboard stay yours** and nothing of yours is changed: the tour runs in a sandbox, and the Start menu's power commands are refused there ([testing.md](testing.md#the-guard-what-a-click-in-the-session-cannot-do)). Cancel any time (the button, or Ctrl+C in the terminal): the run stops within a step, the sandbox is thrown away and nothing is kept.

Do not run two at once, and do not hover a Preview on your real desktop while the hero or the taskbar clip is filming: their Peek shares a state file with your shell ([testing.md](testing.md#6-what-went-wrong-on-the-way-and-the-rule-it-left)).

Retake a tour when a step of it changes (a menu row moves, a label is renamed), and look at the result before you commit it: it clicks the real Dock, so a changed layout can make it miss. `scripts/sheet /tmp/hero.avif` makes a contact sheet of it.

## What you need

- **Hyprland** (it uses its `hyprctl` and the `hl.*` Lua API of 0.56) on **Omarchy**, and you run the recorder from inside it.
- **Tools**: `hyprctl`, `jq`, `grim`, `ffmpeg` (with `drawtext`, and `libaom-av1` for an `.avif`), ImageMagick (`magick`), `quickshell`, `wtype`, `dbus-run-session`, `foot`, and `gcc`, `wayland-scanner` and `pkg-config` with the Wayland client library (to build the pointer client on the first run; Arch: `wayland`, `wayland-protocols`, `gcc`). The recorder checks for them and says which one is missing.
- **The Pins.** The tours pin five apps, which have to be installed (`TOUR_PINS` in `scripts/tours/common.sh`: Files, Ghostty, Edge, VS Code, Obsidian); the recorder says which one is missing. Change the list to what the machine has.
- A monitor tall enough for the strip and the view window (about 1,050 px).

## What happens when you run it

1. **A far monitor** (`TOURTEST`, 1280×800) is created 20,000 px to the right of your screens, out of reach of a real pointer.
2. **The sandbox** is built: a home with a minimal `shell.json` that loads this plugin (linked to your checkout, so it shows the code you are working on) with the settings the tour starts from, links to your themes, and the guard in front of `PATH`. The tour's `tour_prepare` runs against it (`$HOME` is the sandbox).
3. **The nested session** starts: a second Hyprland and a second Omarchy shell (your bar layout, the theme's wallpaper) as a window of your compositor, which is sent to the far monitor, and only then does the shell start. The red strip and the **view window** open on your screen.
4. `tour_setup` runs (windows are opened for the Dock), then **filming starts**: `grim` takes a frame of the session over and over, each stamped with its time.
5. `tour_play` runs: the steps, moving a *virtual* pointer and typing on a *virtual* keyboard inside the session. Each `cap` shows a caption from then until the next one, and the strip shows the step.
6. Filming stops and the session ends at once. The frames become a video, the captions are drawn on it with `ffmpeg`, and it is turned into an AVIF or GIF (10 frames a second, 1000 px wide, or the width of the crop).
7. The recorder compares your real files (`TOUR_REAL_UNCHANGED`) with their fingerprints from before, and fails the run if any changed. The strip turns green and says the recording is saved. The recording's frames (about 1.5 GB in `/tmp`) are removed. The same cleanup runs when you cancel, press Ctrl+C, or the run passes `TOUR_MAX_SECONDS`.

## Writing a tour

A tour is a story, not a feature list: one thing a person does per step, with a caption in plain words. Aim for about a minute and a half for the hero, and twenty seconds for a clip.

### 1. A minimal tour file

```bash
# shellcheck shell=bash
source "$HERE/tours/common.sh"        # the plugin, its Pins and settings, the helpers below
TOUR_OUT=screenshots/example.avif     # where --install puts the result; .avif or .gif picks the format

tour_setup() {                        # runs before filming: windows for the Dock
  pose org.gnome.Nautilus "Documents" 2a3550 2
  settle_focus
}

tour_play() {
  cap "Hover an icon for a live preview"
  read -r x y < <(item_center '.appId == "org.gnome.Nautilus"')
  glide "$x" "$y"
  sleep 2.5
}
```

Run it with `scripts/tour.sh path/to/example.tour.sh` (add `--install` to copy the result to `TOUR_OUT`). `scripts/tours/hero.sh` is a worked example.

### 2. The common part: `scripts/tours/common.sh`

It sets what every StartBar tour needs: `TOUR_PLUGIN_ID`, `TOUR_PLUGIN_WIDGET=0` (a service, not on the bar), `TOUR_PLUGIN_ENTRY` (the Dock as the README shows it, with the Pins), `TOUR_REAL_UNCHANGED` (the real `shell.json` and `~/.local/share/applications`), `tour_requires` and `tour_keys_ok`, and the helpers:

| Helper | Does |
|---|---|
| `item_center 'JQ-TEST'` | prints `X Y`, the centre of the first Dock Item the test picks (`.appId == "btop"`, `.kind == "pin"`, `true` for the first), waiting up to 5 s |
| `menu_rect NAME` | prints `X Y W H` of an open menu (`start`, `item`, `bar`, `barSub`, `preview`) once it has stopped sliding, waiting up to 5 s |
| `start_button` | prints `X Y` of the Start button on a bottom Dock with the icons on the left |
| `pose CLASS TITLE COLOUR WORKSPACE` | a terminal posing as an app of that class: the Dock gives it that app's icon, and its Preview shows the title on the colour |
| `close_windows CLASS` | closes the windows of that class |
| `settle_focus` | no window is the active one (see [testing.md](testing.md#6-what-went-wrong-on-the-way-and-the-rule-it-left)); call it at the end of `tour_setup` after posing windows |
| `settings_up` | is the settings window up |

The positions come from the Dock itself (`omarchy-shell io.github.bmaltais.startbar layout`), so they follow the Pins and the windows. The settings window's are fixed: it opens at its default size, centred (search box at 640,120 on the 1280×800 screen, pages at x=299 and y=213 for Taskbar, 253 Windows, 293 Start menu, Colors and Position in the Taskbar page at y=293 and y=251; `scripts/dev settings` and `scripts/dev shot` show them).

### 3. Keys, and the window they go to

Keys and typing are only sent while the Start menu or the settings window is up, so they can never land on anything else. The Start menu is part of the Dock's own surface, so it is not a layer of its own: the tour defines `tour_keys_ok` (in `common.sh`: the settings layer is mapped, or the Dock reports an open Start menu), which the recorder uses instead of `TOUR_LAYER`.

### 4. Find where to click, look at it, tune the timing

Use the test session ([testing.md](testing.md)): `scripts/dev up`, `scripts/dev run foot -a foot sleep 600`, `scripts/dev layout`, `scripts/dev shot /tmp/a.png`. Run a tour without `--install` and look at the result with `scripts/sheet /tmp/example.avif --every 4`. Give each caption enough time to be read (the recorder holds it for its reading time, below), and let animations finish before the next click; use `wait_until` for what takes as long as it takes, not a fixed `sleep`.

Two things the session does that a real desktop does not: a right-click on an Item of a Dock on the top or left edge closes its menu at once, so right-click Items on a bottom Dock; and the windows are one per workspace (`pose`'s last argument), so that a Peek shows that window alone.

### 5. Making changes safe

The tour runs in a sandbox, so what it changes is thrown away. Anything it must not touch is listed in `TOUR_REAL_UNCHANGED` (paths under your real `$HOME`): the recorder fingerprints them before and after and fails the run if one changed. The StartBar tours list the real `shell.json` and the applications folder. A tour that needs data from your home lists it in `TOUR_SANDBOX_COPY`; the StartBar tours copy nothing.

## Clips

A tour with `TOUR_CROP=WxH+X+Y` keeps only that box of the session's screen, so a short tour of one part can stand in for a still image. The README's clips are `scripts/tours/taskbar-clip.sh`, `icon-menu-clip.sh`, `start-menu-clip.sh`, `bar-menu-clip.sh` and `settings-clip.sh`, each 14 to 21 seconds and 50 to 220 KB as an AVIF. `scripts/clips.sh` records them all.

- **No captions**: the crop is small. A clip is meant to be read as a picture.
- **Loop it.** Start and end on the same picture: the Dock idle, the menu closed, or (the settings clip) the window opened in `tour_setup` and the page it began on.
- **The wallpaper stays.** The flat backdrop (`TOUR_BACKDROP=plain`) the other Start apps use is a full-screen window, which Hyprland may draw over the Dock (a Top layer); it was not tried here. The clips show the theme's wallpaper, as the stills do.
- Run it like any tour: `scripts/tour.sh scripts/tours/settings-clip.sh [--install]`. Each run starts its own session (about a minute of set-up and encoding).

## Reference

### Variables a tour file sets

| Variable | Meaning | Default |
|---|---|---|
| `TOUR_TITLE` | The app's name, for the strip. **Required** (`common.sh` sets it) | |
| `TOUR_PLUGIN_ID` | **Required.** The plugin's id, to load in the sandbox | |
| `TOUR_PLUGIN_ENTRY` | A JSON object merged into the plugin's entry in the sandbox's `shell.json`: the settings and Pins it starts with | `{}` |
| `TOUR_PLUGIN_WIDGET` | `0` for a plugin with no bar widget (a service): loaded, not put on the Omarchy bar | `1` |
| `TOUR_OUT` | The result's path in the repo, used by `--install`. Its extension picks the format: `.avif` (animated AVIF) or `.gif` | `screenshots/hero.avif` |
| `TOUR_LAYER` | The app window's layer-shell namespace; needed for `typed`, `esc` and `pressed` unless the tour defines `tour_keys_ok` | none |
| `TOUR_STEPS` | How many steps (`cap` calls), for "Step 2 of 6" | unknown |
| `TOUR_SIZE` | The session's screen, `WxH` | `1280x800` |
| `TOUR_CROP` | `WxH+X+Y`: keep only that box of the screen, for a clip | the whole screen |
| `TOUR_BACKDROP` / `TOUR_BG` | `plain` puts a flat colour over the wallpaper (not tried with the Dock: see Clips) | the wallpaper |
| `TOUR_SANDBOX_COPY=(path …)` | Paths under `$HOME` to *copy* into the sandbox | none |
| `TOUR_SANDBOX_LINK=(path …)` | Paths under `$HOME` to *link* read-only (the icons) | none |
| `TOUR_REAL_UNCHANGED=(path …)` | Paths under your real `$HOME` that must not change: fingerprinted (name, size, mtime) before and after; a difference fails the run (exit 1) and keeps nothing | none |
| `TOUR_MAX_SECONDS` | Stop a tour that runs longer than this, as a stuck step would | `300` |
| `TOUR_FONT` | The caption font file | JetBrains Mono Nerd Font Bold |
| `TOUR_GIF_WIDTH` | The width in pixels of the result, whichever format (10 frames a second) | `1000`, or the width of `TOUR_CROP` if smaller |
| `TOUR_AVIF_CRF` | AVIF quality, lower is sharper and bigger | `40` |
| `TOUR_GIF_COLORS` | For a `.gif` result: its palette size | `128` |
| `TOUR_KEEP_TMP` | `1` keeps the run's folder (frames, the session's log) in `/tmp`, for looking at a run that went wrong | `0` |

### Functions a tour file defines

| Function | Runs | Use it to |
|---|---|---|
| `tour_requires` | first, with your real home | check what the tour needs; print a reason and return non-zero if it is missing |
| `tour_prepare` | before the session starts, with `$HOME` the sandbox | reset to a known state |
| `tour_sandbox DIR` | while the sandbox is built (optional) | adjust the copies |
| `tour_setup` | once the session is up, just before filming | make the changes that must be visible in the film. Only `common.sh`'s helpers are there yet, not the recorder's (`wait_until`, `layer_up`) |
| `tour_keys_ok` | before each key | say whether the window is up |
| `tour_play` | while filming. **Required** | the steps |

### Helpers for `tour_play`

| Helper | Does |
|---|---|
| `cap "text"` | Shows this caption, at the bottom, from now until the next `cap`. Also updates the strip. Avoid `:` and `'` in the text (they are special to `ffmpeg`). |
| `glide X Y` | Moves the pointer there in small steps, so it is seen to travel. Over a Dock Item it opens the Preview after its delay. |
| `click X Y [pause]`, `rclick X Y [pause]` | Glides there, clicks with the left or right button, then waits `pause` seconds (default 0.9). |
| `scroll X Y N [pause]` | Glides there and turns the wheel N notches (positive: down). |
| `drag DX DY` | Presses the button where the pointer is, moves by that much, lets go. |
| `typed "text"` | Types it, slowly enough to be seen. |
| `esc`, `pressed KEY` | Presses Escape, or that key (`Return`, `Down`, `BackSpace` ...). |
| `wait_until 'command' [seconds]` | Polls a shell command until it succeeds, up to `seconds` (default 30). |
| `at X Y` | Puts the pointer there at once. |
| `W`, `H`, `TMP`, `REPO`, `HERE` | The session's size, a scratch folder, the repo root, the scripts folder. |

Other commands in `tour_play` are ordinary shell: `hyprctl`, `omarchy-shell` and `grim` act on the nested session, so a tour file works out paths when it uses them (`$HOME/…` inside a function), not when the file loads.

## How it works inside

The same as the test session ([testing.md](testing.md#5-how-it-works-inside)), plus:

- **Frame timing.** The frames are joined with `ffmpeg`'s concat demuxer, each shown for the time until the next one, so the video plays at the speed things really happened even though grabs take a variable time. **Captions** are drawn by `drawtext`, each enabled between the time it was said and the time of the next.
- **The result** is an **animated AVIF** by default (AV1 video in an image file, made with `libaom-av1`; `TOUR_AVIF_CRF`) at 10 frames a second: the hero is about 0.5 MB, a GIF of it several times that. It plays in an `<img>` in modern browsers, and GitHub serves it as `image/avif`. A `.gif` (`TOUR_OUT=....gif`) is the fallback for anywhere that cannot show AVIF. **ffprobe shows an AVIF's first image only** (the still cover); the animation is the second video stream, so use `ffprobe -f mov` or `-map 0:v:1`.
- **The red strip** (`scripts/tour-banner.qml`), run by `quickshell` as its own small instance: a top-anchored, always-on-top layer-shell window on your real monitor, with a **Cancel recording** button (it writes a file the recorder watches) and a text file the recorder rewrites at each step. It turns green at the end and grey when cancelled.

## Troubleshooting

- **"window not up, skipped keys …"**: the Start menu or the settings window was not up when the keys were due. A step before it did not open it, or closed it (Escape backs out one layer at a time: search text, All apps, then the menu). Fix the earlier step; use `menu_rect start` or `wait_until` rather than `sleep` if the window can be slow.
- **Clicks miss**: the layout is not what you measured. Items come from `item_center`; the settings window's are fixed, so check it opened at its default size.
- **"the item menu did not open"**: right-clicks on Items of a Dock on the top or left edge do not work in the session; use a bottom Dock for them.
- **The film is on the wrong workspace after a Preview**: a posed window was left as the active window. End `tour_setup` with `settle_focus`.
- **The run is slow and the film shows the wallpaper**: `/tmp` was full. Look at `df -h /tmp`; a run removes its frames now, an older one (or another Start app's) may not have.
- **A run was killed with `kill -9`**: the cleanup did not run. `hyprctl output remove TOURTEST`, and stop the leftovers: the `quickshell` running `tour-banner.qml` and `dev-view.qml`, and the nested Hyprland (they carry the sandbox's `XDG_CONFIG_HOME`, see `nested_procs` in `scripts/nested/session.sh`). Nothing of yours needs restoring. Remove the run's folder in `/tmp` by hand (`TOUR_KEEP_TMP` or a killed run leaves it).
- **The AVIF is too big**: shorten the tour, raise `TOUR_AVIF_CRF`, or lower the width.
- **A step waits forever**: `TOUR_MAX_SECONDS` ends the run and says so.

## Human-like input

People do not move a mouse in straight lines at a steady speed or type at metronome intervals, and an animation of a robot looks fake. By default (`TOUR_HUMAN=1`) the recorder moves and types the way the research and the existing emulators describe. `TOUR_HUMAN=0` gives plain, even motion; `TOUR_SEED=N` makes the randomness repeatable.

**The pointer** (`glide`, `click`, `drag`; `scripts/nested/vptr.c`): movement time follows Fitts's law (0.15 + 0.12 · log2(distance / 40 + 1) seconds), speed the minimum-jerk curve (Flash & Hogan 1985), the route a cubic Bézier bowed to one side by at most about 15 px (as in [ghost-cursor](https://github.com/Xetera/ghost-cursor)), with correlated wobble like [WindMouse](https://windmouse.readthedocs.io/en/latest/algorithm.html), an overshoot of 2 to 5 px on a move over 500 px in about 30 % of cases, a landing within 2 px of the target, and a rest of 0.15 to 0.45 s before a click.

**Typing** (`type_chars`): each gap is log-normal (median 118 ms, never below about 60 ms), a little quicker when the next key is under the other hand, slower after a space. The figures come from Dhakal, Feit, Kristensson and Oulasvirta, ["Observations on Typing from 136 Million Keystrokes"](https://userinterfaces.aalto.fi/136Mkeystrokes/), CHI 2018. Not modelled: mistakes and corrections, key rollover, pauses to think.

## Reading time

A caption that vanishes before it can be read is useless, and a viewer reads a new caption before looking at what the pointer does. A caption is held at least 0.95 s plus its words at 150 a minute (`TOUR_READ_WPM`), and never under 2.5 s; the first pointer or key action after a caption waits 0.5 s plus its words at 238 a minute (`TOUR_LEAD_WPM`, the average silent reading rate for English adults, Brysbaert 2019). `0` turns either off. The tour prints the result for each caption (`tour: caption 3 (4 words) on screen 4.3 s (reading time 2.5 s)`).

## Using it in another Start app

The recorder has no StartBar in it except `scripts/tours/` and the guard's list of commands in `scripts/nested/session.sh`. See "Shared with the other Start apps" in [testing.md](testing.md#shared-with-the-other-start-apps) for what StartBar added to the shared files, and `README.md` for how the animation sits in a `<picture>` so that GitHub does not turn a click into a link to the file.

## Decision log

Newest first.

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | StartBar adopted StartDrive's test session and recorder (it had filmed a virtual monitor with the real pointer and the shell restarted) | The old way moved the maintainer's pointer, restarted their shell and acted on their windows; the nested session does none of it, and the three Start apps keep one set of scripts |
| 2026-10-15 | The session runs behind a guard that refuses the Start menu's power commands, and does not start without it | A nested session shares the user's systemd and login session: a click on Shut down would have shut the machine down |
| 2026-10-15 | The README's tour and clips are animated AVIFs in `<picture>` tags, replacing `hero.gif` (3.7 MB) | About a seventh of the size, sharper, and GitHub does not link a `<picture>` to the file |
| 2026-10-15 | The recorder removes its frames when it ends | Each run left 1.5 GB in `/tmp`, which is memory: a few runs made everything that wrote there fail |
| 2026-10-15 | The shell in the session starts after the window has its final size | Started before, it reported the first size as its screen's and `layout` answered with wrong pixels |
