# Verification

Run the deterministic checks from the repository root:

```bash
python3 -m unittest discover -s tests -v
npm --prefix vendor/startbar test
```

The bundle tests cover preservation of unrelated shell settings and taskbar pins, repeatable configuration changes, package-hold placement and removal, snapshot restoration of files/directories/symlinks, backup path validation, frozen plugin copies, snap geometry, and rejection of invalid window addresses and rectangles before dispatch.

Activation loads the installed Hyprbars binary explicitly before reloading the configuration. [Hyprland 0.56.2 caches its configured plugin paths](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/plugins/PluginSystem.cpp); unloading a plugin and reloading an unchanged path list does not load it again. The installer also writes the main Hyprland entry point after the remaining assets are ready.

The StartBar suite contains 367 tests, including the minimize dispatch, command validation, window-metadata privacy checks, and diagnostic log regressions. Its upstream QML check currently reports six existing warnings on the pinned baseline; those warnings are also present in an unmodified checkout of the same revision. Do not treat that aggregate check as passing. The vendored shell lint wrapper also references a missing `.githooks/pre-commit`; direct Bash syntax checks passed for all 26 scripts, but ShellCheck was not run.

For the security-review delivery, all 14 bundle tests and all 367 StartBar tests passed.

The three privacy regressions execute `focusWindow`, `focusWindowAndWarp`, and `rescueWindows` against a stub compositor and real Bash/jq. A jq wrapper records its arguments while fixtures supply a selected window's title, an unrelated window's initial title, and a monitor description. All three tests failed on the previous implementation because those values appeared in the arguments. The fix reads both JSON snapshots through anonymous pipes using Bash process substitution and jq slurp input. The tests also require an off-screen window to be centered, so dropping the recovery operation cannot satisfy them. No real desktop titles are used.

Four diagnostic regressions execute `scripts/hypr-events.sh` with a synthetic event source. They check permissions on new and existing logs, literal handling of a quote-containing filename, private default log and PID placement, and rejection of invalid runtime directories. The original permission and injection reproductions failed before the fix. The test processes run in disposable directories and only their own process groups are terminated. See [SECURITY_REVIEW.md](SECURITY_REVIEW.md) for the findings, coverage, static-analysis results and remaining limits; independent security approval remains pending.

Graphical behavior is checked in a separate Hyprland session with a temporary home directory and virtual input. The checks include taskbar minimize/restore, maximize hover without stealing keyboard focus, all six snap layouts, keyboard opening and dismissal, outside clicks, native maximize, clicking overlapping floating windows, and native Wayland minimize requests. Application tab selection and reordering were also checked in an isolated Maestri profile.

With a separate StartBar development session already running with one 1920x1080 output, run this regression from the repository root in your original desktop environment:

```bash
python3 tests/check_browser_focus.py
```

It requires the built `build/hyprbars.so`, Chromium, Foot, Grim, ImageMagick, GSettings, and the virtual pointer built by StartBar's development tools. The check reads the isolated session's state, refuses to target the current desktop, and opens a fresh Chromium profile plus a disposable terminal. It checks both keyboard focus and a pixel in the overlapping region: a successful focus change alone would miss a browser remaining behind the terminal. It also checks that hovering preserves focus and that clicking an exposed part of the terminal raises it again. Only the test applications are closed afterward.

The check reloads configuration only in the isolated session before applying Omarchy's stock maximize-suppression rule, the stock browser rules, and this bundle's configuration. Native button placement uses a private GSettings keyfile backend. It checks native maximize and restore through both Chromium's button and title-bar double-click, verifies a pixel outside the restored window's bounds, and checks that unloading restores stock suppression and reloading enables an already open window. A failed maximize or restore saves a diagnostic screenshot inside the isolated development session directory.

The pointer's `stream` mode keeps one virtual mouse connected between actions, so native double-clicks use the same Wayland pointer. Start it with `vptr stream 0 0 1920 1080`; it accepts `move X Y` and `click X Y` lines on standard input, acknowledges each completed action with `ok`, and exits at end of input. The regression uses a maximized Chromium window to check activation in both directions: the terminal must become visible over the browser, and clicking the browser must cover the terminal again. Before the activation fix, Chromium received focus while the overlap pixel stayed terminal red. With the fix, the overlap becomes browser blue. Other unpinned floating windows stay open in the same workspace.

The disposable terminal also checks Hyprbars double-click maximize, button restore, minimize, close, and dragging from maximized. Before the title-bar drag fix, moving the pointer by two pixels during a click moved the terminal, and dragging a maximized terminal restored it at a negative vertical position with its controls above the screen. Hyprbars now waits for four logical pixels of movement before starting a drag, cancels double-click tracking when a drag starts, and restores a maximized window with the grabbed title-bar position under the pointer. The regression includes a double-click with two pixels of movement between press and release.

The native maximize regression exposed two separate constraints. Suppression rules are additive, so `suppress_event = "none"` does not remove Omarchy's existing maximize block. [Hyprland also advertises a maximized state when mapping Wayland windows to suppress client decorations](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/protocols/XDGShell.cpp#L528). Clearing the block alone lets the first request through but leaves Chromium's native controls out of sync. The modified Hyprbars permits the requests and synchronizes the advertised state on activation and fullscreen-state changes. The live Chromium maximize/restore button was confirmed by the desktop user, and its native title-bar double-click was checked in the same session. Earlier live Foot button and double-click checks also passed.

The browser regression initially failed with Chromium focused but still tiled beneath the terminal. Omarchy's `chromium-based-browser` tag rule was being reapplied after the general class rule. [Hyprland 0.56.2 rechecks static rules matching changed tag properties](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/desktop/rule/windowRule/WindowRuleApplicator.cpp#L526), so a later floating rule using that same tag is required. With that override, a newly opened Chromium window remains floating and the rendered overlap changes to the browser after a click. Existing tiled windows are still converted by installer activation.

Native minimize requests passed with GTK windows using both Wayland and XWayland. The actual `Win+Z` key combination was also checked, including that it does not open Start accidentally. A full reboot has not been exercised, and the package snapshot has not been tested on another machine. See the README's native-title-bar and application-tab limits before changing the pinned stack.

A staged installation was restored in the isolated session and every managed path matched its backup, including symlinks and file modes. Live installation was also checked for package holds, loaded binary, preserved taskbar pins, preserved status widgets, and floating state of existing windows.
