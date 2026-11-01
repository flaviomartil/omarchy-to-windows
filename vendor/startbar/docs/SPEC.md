# StartBar: specification

What StartBar does today. Vocabulary is defined in [CONTEXT.md](../CONTEXT.md); capitalised terms below refer to it. Decisions that shaped it are in [docs/adr/](adr/).

## Identity

- Omarchy shell plugin, id `io.github.bmaltais.startbar`, display name "StartBar", licence MIT.
- Kind `service` with `keepLoaded: true`; the plugin owns its own layer-shell surfaces.
- This repository's root is the plugin directory (`manifest.json` at the root), so `omarchy plugin add <git-url>` installs it. The development install is in [CONTRIBUTING.md](../CONTRIBUTING.md).
- Listed on the Omarchy plugin marketplace.

## What the Dock shows

- One Dock per monitor: a full-width bar along the bottom edge with the Start button, the Items and an optional clock. Every Dock shows the same Items.
- One Window Item per Window, across all workspaces and all monitors, including special workspaces.
- A Window whose App cannot be resolved shows a Letter Tile and cannot be pinned.
- An App whose icon file Qt cannot find shows a Letter Tile with the first letter of its name (the Start menu leaves the icon blank), and the Dock and the Start menu, sharing one lookup (`IconResolver.qml`), search the icon directories for the file itself: at once, then every ~10 seconds, three searches in all. If it finds one the icon replaces the tile. (Qt remembers a miss until the shell restarts, so an icon installed after the App was first looked up, such as a package installed while the shell runs, would otherwise stay blank.)
- Grouping (`groupWindows`, true; added 2026-10-10): with it on, an App's Windows collapse into one Group Item when it has two or more; a lone Window is a plain Window Item as ever. See "Grouping" below.
- Pins: an App kept in the Dock whether or not it has Windows. A Pin holds a slot; while its App has Windows their Window Items occupy that slot, otherwise the Pin is shown and launches the App on click. A Pin whose App is no longer installed shows a Letter Tile with a "missing" tooltip and stays until unpinned.
- Ordering: Launch Order, with a new Window joining the Window Items of its own App. Any Item may be dragged to a Placed position; a Placed Pin keeps it permanently, a Placed Window Item until the Window closes. Dragging one Window of a pinned App moves only that Window.
- Indicators: a small pill under every Window Item, wide and accent-coloured for the Active Window, which is also highlighted; a workspace badge on every Window Item when `showWorkspaceBadge` is on (default off); an urgent-colour tint for Attention. No magnification.
- Previews (`showPreviews`, on): hovering a Window Item shows its Preview, a live thumbnail with the title and a close button. The thumbnail keeps the Window's own aspect ratio inside a fixed-size box and holds its last good frame if the live capture blanks. A Pin without Windows shows no tooltip, as in Windows (a missing one still does). With previews off, a Window Item shows a tooltip with its title and workspace.
- Slide (`previewSlide`, true): the Preview rises out of the Dock edge (clipped by its own box) over ~200ms when it appears; closing it is instant, and moving to a neighbouring Item closes it at once and slides that Item's up after the open delay.
- Peek (`previewPeek`, true; added 2026-10-10): hovering a thumbnail for 150ms shows that Window by focusing it, as Windows' Aero Peek does: its workspace comes into view, and a maximized or full-screen Window covering it on that workspace is un-maximized for the peek. Moving to another thumbnail first undoes the previous peek, then applies the new one. Leaving the thumbnails (200ms) or closing the popup restores the focused Window, each monitor's workspace and the maximized state; a click on the thumbnail keeps the Window focused instead. State is saved in `$XDG_RUNTIME_DIR/startbar-peek` and any leftover is restored when the shell starts. Hyprland cannot unset a window's opacity, so the peek focuses rather than fading other windows.
- Overflow: icons shrink until every Item fits the monitor width.
- Colours and fonts come from the current Omarchy theme and follow theme switches live, unless a fixed palette is chosen (see "The bar").

## The bar

- Full-width along the bottom (or the top, left or right edge, see "The Dock's position"), `barHeight` (48) tall, with `opacity` (0.9) or `transparent` (icons only). While Omarchy's bar is Glassy (`bar.background` in `shell.json`), the Dock's opacity is at most 0.35 and the Start menu's card is see-through (0.6), and StartBar asks Hyprland to blur behind both (a layer rule on `omarchy-startbar`, set at start and after a config reload; it has no effect while Hyprland's blur is off). Menus, Previews and the settings window stay solid: Hyprland does not blur those surfaces.
- Icons are `iconSize` (48) at most and also fit inside the bar (`barHeight - 20`), so with the defaults they are 28px.
- `alignment`: `left` (default, changed from `center` 2026-10-10) or `center` for the group of Start button and Items.
- Start button (`showStart`, on) at the start of that group. It runs `startCommand`, which is `builtin` by default and opens the Start menu; any other value is run as a command, such as `omarchy-menu toggle apps` for the Omarchy menu. `startIcon` is `grid` (drawn by the plugin, the default), `omarchy`, `arch`, `linux`, an icon-theme name, or an absolute image path.
- Clock (`showClock`, off) at the right end.
- `colorScheme`: `theme` (default) follows Omarchy; `dark` and `light` are fixed palettes. It applies to the bar and everything that rises from it: the Start menu, the menus and the Previews. Tooltips and the settings window always follow the theme.

## How the Dock behaves

- The Dock floats on the Top layer and by default reserves no screen space, so maximized and fullscreen windows cover it. `reserveSpace` (off) makes it reserve its bar's thickness on its edge, so windows stop at it: a transparent, input-less window on the Bottom layer holds the space, on each monitor, and only while auto-hide is off (a hiding Dock never reserves).
- It is always Revealed unless `autoHide` is on (default off).
- Reveal: with auto-hide on, the Dock is Hidden by default and the Reveal Strip spans the full bottom edge of each monitor, above any space the Omarchy bar reserves. The pointer resting on it for the reveal delay (`revealDelayMs`, 200 ms) makes the Dock Revealed; it returns to Hidden after the hide delay (`hideDelayMs`, 300 ms) once the pointer leaves it. It slides up from the edge in about 150 ms. Without auto-hide there is no Reveal Strip and no timers run.
- With auto-hide on, the Dock stays Revealed while a menu or the Start menu is open, while the pointer is on the Start button, and for the whole of a drag; the hide timer starts after the drop or the close.
- Attention never reveals the Dock by itself.

## The Dock's position

- `position`: `bottom` (default), `top`, `left` or `right`: the edge of each monitor the Dock sits on. Every monitor's Dock takes the same one.
- On the top edge everything is the mirror image of the bottom: the Reveal Strip spans the top edge (below any space the Omarchy bar reserves there) and the Dock slides down from it; a Preview opens below its Item, sliding down out of the Dock edge; the Item menu and the Bar menu open below the Dock; the Start menu's top edge is just below the Dock; the bar's 1 px border is on its lower edge.
- Spacing, as on Windows 11: a Preview, the Item menu, the Bar menu and the Start menu all stand `edgeSpacing` (12) px from the bar's edge (not from the Item inside it), the same as the Start menu's side margin when icons are left-aligned (the Start button's padding is `edgeSpacing` too). The Start menu's own distance to the screen's edge is that padding, so the space at its side and above the bar match.
- Chosen in the Bar menu (Position: Bottom, Top) or the settings window; it applies live.
- On the left or right edge the Dock is a column `barHeight` wide, the full height of the monitor (below any space the Omarchy bar reserves). What is said below of the left edge holds for the right with left and right swapped. The exception is the Bar menu, whose section chevrons point left from the menu's left edge, with the submenu opening on its left. The Start button is at its top, then the Items downward, and the clock, if on, at its foot with the time over a short date (`d MMM`). `alignment` means the top of the column (`left`) or its middle (`center`). The running dots stand in a column on the outer side of each icon (left on the left edge, right on the right), level with it, instead of under it, and Items shrink to fit the column's height as they do a row's width. The Reveal Strip is a `revealStripHeight`-wide band down the left edge, and the Dock slides in from it.
- Also on the left: a Preview opens to the right of its Item, level with it, and slides out sideways; the Item menu opens to the right of its Item and the Bar menu to the right of the bar, level with the pointer; the Start menu stands beside the bar, its top level with the Start button (`left`) or centred on the screen (`center`). Dragging works along the column: dragging an Item off the bar sideways, by half an icon, is the drag-out.
- The running dots stand above each icon on the top Dock, below on the bottom one.

## Input

- Focusing a floating Window from the Dock (a click on its Item or Preview) also raises it above other floating Windows (added 2026-10-11): Hyprland's focus alone leaves it underneath, focused but hidden. Tiled Windows are not raised. A peek raises a floating Window too, since a peek of one left under another would show nothing; it stays raised after the peek is put back, because Hyprland has no way to put the order back.
- Workaround (added 2026-10-14, may need revisiting if Hyprland or Omarchy stops leaving them): a floating Window that sits outside every monitor (left behind when its monitor went away) is centered on its monitor when its Preview opens (so the thumbnail has something to show) and when it is focused from the Dock, so a click on its Item or Preview shows it. A Window with at least 64x32 px on some monitor, and any tiled Window, is left where it is. It only happens when a Preview opens or a Window is picked, never on a monitor change or when a Window opens, and there is no setting.
- Left click on a Window Item: focus the Window, switching workspace and monitor as needed; a minimized Window is restored. Clicking the Active Window's Item minimizes it to `special:minimized` and dismisses its Preview. Clicking it again restores and focuses it.
- Left click on a Pin with no Windows: launch the App.
- Middle click on any Item with a resolvable App: launch a new instance.
- Click on a Preview: focus its Window and, with `previewWarpPointer` (on), move the pointer to the middle of that Window. Clicking an Item itself never moves the pointer.
- Right click on a Pin with no Windows: the App's own desktop actions, then a row with the App's icon and name that starts it, then "Unpin from taskbar" with a struck-through pin glyph (only the unpin row for a missing Pin).
- Right click on a Window Item: the Item menu, in four groups. (1) The App's own desktop actions (e.g. "New Private Window"). (2) For a Window Item, its state: Maximize/Restore, Full screen/Exit full screen, Float/Tile, and, when floating, Center and Pin on top/Unpin from top; Move to scratchpad (hidden once there). (3) The App's icon and name, which starts another instance, then "Pin to taskbar" (a pin glyph) or "Unpin from taskbar" (the struck-through pin); a Letter Tile Item has no App, so no group (3). (4) Close window (an X glyph; "Close all windows" for a Group Item). The state rows act on that Window whether or not it is focused. The menu stays open until a row is chosen, a click lands outside it, or the pointer leaves it.
- Right click on a Preview (added 2026-10-11): the Preview menu for that one Window, with its bottom-left corner at the pointer, as in Windows 11: its state rows (as in the Item menu's second group) and Close Window. A peek in progress is left as it is while the menu is open (restoring it would change focus and close the menu); choosing a state row keeps that Window focused, as a click does, and closing the menu any other way puts the peek back. The Preview stays up while the menu is open; the Preview goes after the menu closes if the pointer has left it. Choosing a row acts on that Window whether or not it is focused. Unlike the Item menu it has no App rows (the App's icon and name, Pin to taskbar): those are about the App, and the Item menu has them.
- Right click on the bar (not on an Item): the Bar menu, kept short by folding related options into five sections, each opening a submenu: a second popup beside its row, level with it (on the left when the screen has no room), opened by resting the pointer on the row or clicking it, and replaced when the pointer moves to another section. Leaving the row toward the submenu does not close it (a 250 ms grace), moving to a plain row does. The sections are Icon alignment (Left, Center), Position (Top, Left, Right, Bottom), Colors (Theme, Dark, Light), Start button (show it; open the built-in or the Omarchy menu; open on hover) and Window previews (show them; show the window on hover; pointer follows click). Then, divided, the everyday toggles (auto-hide, clock, group windows, workspace badge, transparent background) and Settings…. Rows that mean nothing while another setting is off (the preview options with previews off, open-on-hover with no Start button or with the Omarchy menu) are dimmed and inert. Hide Omarchy's dock is only in the settings window. Choosing a setting row writes it and closes the menu; the submenu and the menu close together; the bar updates live.
- Drag within the Dock: reorder. A pressed Item shrinks a little; once lifted it is drawn a little bigger than the others, and the Items between its slot and the one under it step aside to show where it would land. It stops at the first and last slot while the pointer goes on, and never goes past the Start button. Drag out of the Dock (up or down, off the bar): unpin the Item's App if pinned, otherwise snap back.
- The Dock never takes keyboard focus. The two exceptions are the Start menu while it is open and the settings window.

## Start menu

With `startCommand: "builtin"`, the default, the Start button opens StartBar's own menu, anchored above the button (the Omarchy menu always centres on screen and can't be anchored). With centred icons it is centred on the monitor.

- Opening: a click on the Start button, or, with `startHoverOpen` (off by default, changed from on 2026-10-10), the pointer resting on the Start button for 400 ms.
- Hover mode: a menu opened by resting the pointer. It already has the keyboard, so typing searches at once, but it closes 500 ms after the pointer is on neither the button nor the menu. Clicking the Start button does not make it stay, and moving the pointer on to an Item closes it at once so that Item's Preview takes over. Typing a key, or clicking the search box, ends hover mode: the menu then stays until dismissed, like a clicked-open one.
- From the keyboard: `omarchy-shell io.github.bmaltais.startbar startMenu` toggles it on the focused monitor and `closeStartMenu` closes it, for a Super-key binding. It never opens in hover mode this way. With a `startCommand` other than `builtin`, both the button and this command run that command instead.
- Search box at the top: type to filter all Apps; Up/Down move the highlight and Enter launches it. It, and the text fields in the settings window, are not native text controls, because Qt reads the clipboard whenever it changes with no size limit, which a hostile clipboard owner can use to stall the shell (`PlainField.qml`, `PlainText.js`). They type (up to 256 characters in the search box, 1024 elsewhere), Backspace deletes one character, Ctrl+U or Ctrl+Backspace clears, Enter finishes, and Ctrl+V or Shift+Insert pastes at most 4 KiB of text from `wl-paste` (one line, giving up after a second). There is no caret movement, selection or IME composition.
- Pinned: a six-column grid of Start Pins. Until the list is first changed it shows the Dock's Pins. A tile can be dragged to another slot to reorder, the same way as on the Dock: it shrinks when pressed, is drawn bigger once lifted, the tiles between its slot and the one under it step aside, and it stops at the first and last pin. The order is saved on release; dropping a cell or more beyond the grid changes nothing.
- "All apps ›" switches to an A-Z list titled "All", with letter headings, an outlined "‹ Back" button opposite the title, and each App's generic name under its name when it has one. Clicking a letter heading opens an A-Z jump grid; letters with no Apps are dimmed.
- Recommended: the last six Apps launched (from the menu, or any other way: an App's Window opening counts), each with its generic name (such as "Web Browser") under it when the desktop entry has one.
- Right-click an App: Pin to / Unpin from Start, Pin to / Unpin from Dock, Open.
- Places: a column on the left with Home and the user's XDG folders (Documents, Downloads, Pictures, Music, Videos, read from `~/.config/user-dirs.dirs`; any that is just Home is skipped). One click opens the folder with `xdg-open`. A `startPlaces` list of paths (`~` allowed) replaces the defaults; an empty list hides the column.
- Footer: the account's real name (from the system account, else the login) with the `~/.face` picture cropped to a circle, or an initial when there is none. Clicking it offers Lock and Sign out. A power button offers Sleep, Restart and Shut down. These run Omarchy's system commands and `systemctl suspend`.
- Keys with nothing typed: the arrow keys walk the Pinned grid and then Recommended, and Enter launches the selection. In All apps, Up/Down walk the list.
- Escape backs out one layer at a time: an open overlay menu, the jump grid, the search text, All apps, then the menu itself. Outside hover mode, a click anywhere outside the menu closes it.
- The menu is part of the Dock's own surface, not a popup window: a popup's keyboard grab needs a recent click inside the plugin's window, which hover-opened and keyboard-opened menus lack, so the compositor would refuse it and keys would go to the focused window. While the menu is open the surface takes exclusive keyboard focus, as Omarchy's own menu does.

## Configuration

Stored in StartBar's entry in Omarchy's shell config (`~/.config/omarchy/shell.json`, `plugins[]`), written through the shell's plugin write-back hook. A hand edit to the entry applies live. The entry holds:

- the settings named above; every key and default is listed in [SETTINGS.md](SETTINGS.md)
- `pins`, the Pins in order, and `placements`, each Placed Pin's position (a Placed Window Item's position is never stored: it lasts only until the Window closes)
- `startPins`, `recentApps` and `startPlaces` for the Start menu

- Omarchy dock: `hideOmarchyDock` is on by default. While it is on, StartBar disables Omarchy's own dock plugin (`omarchy-shell shell setPluginEnabled omarchy.dock false`) and enables it again when the setting goes off. It acts only when the setting changes, and on start when it is on, so a dock you disabled by hand stays disabled while the setting is off.

- New window workspace: `newWindowWorkspace` is `off` by default; `normal`, `maximized` and `fullscreen` turn it on (a leftover `true` reads as `maximized`). While on, a Window that opens tiled on a workspace that already has Windows moves to the lowest-numbered workspace with no Window (which is shown) and is put in the chosen state there (`normal` leaves it as it is); a Window that opens alone only gets the state. Floating, full screen and special-workspace Windows are left alone, so dialogs and Omarchy's minimized Windows are unaffected; a Window that Omarchy's floating workspace mode floated counts as tiled. It acts on Hyprland's `openwindow` event, so only while the shell runs, and the Window shows briefly where it opened before it moves.

A value that is missing or unusable falls back to its default. A leftover `style` key from the removed dock style ([ADR 0002](adr/0002-startbar-is-only-a-taskbar.md)) is ignored.

## Grouping

Optional, on by default (`groupWindows`, which can be turned off; also a row in the bar's right-click menu and in the settings window). Modelled on the Windows taskbar. The "one Window Item per Window" rule above holds while it is off.

- Windows of one App (Windows with no App group by window class) become a single Group Item, in the slot Launch Order or the App's Pin gives them. The icon has copies of itself stacked behind it, offset to the right and smaller (at most two), and the running indicator shows one dot per Window (at most three). The Group Item is highlighted when any of its Windows is the Active Window, and tinted when any is in Attention. Its workspace badge shows only when all its Windows are on one workspace.
- Hover: the preview popup shows one thumbnail per Window in a row, each with title and close button; the Active Window's is outlined. Thumbnails shrink to fit the screen. Clicking a thumbnail, its title or the space around them focuses that Window (only the close button closes it); closing one leaves the popup up for the rest, and the last one closing takes it away. With `showPreviews` off the tooltip gives the App name and Window count.
- Left click on a Group Item does nothing (pick from the preview, as on Windows), except with previews off, where it focuses the Window after the Active one. Middle click launches a new instance.
- Right click: the App's actions, and the App row with Pin/Unpin, as for any Item; the Window-state rows are left out; "Close all windows" replaces "Close window".
- Placed: a Group Item's position is kept until the App's last Window closes. Dragging it moves the whole group, and dragging a pinned App's group out unpins the App.

## Settings window

A window titled "Taskbar settings" with a control for every setting, so nothing needs hand-editing. It is a layer-shell window on the Overlay layer, centred on the monitor it was opened from, taking keyboard focus on demand; Escape or the close button closes it.

- Opened from the "Settings…" row of the Bar menu, and by `omarchy-shell io.github.bmaltais.startbar settings` on the focused monitor (`closeSettings` closes it), so it can be bound to a key.
- The window opens centred and can be moved by dragging its title bar (it is kept on the screen, with the title bar reachable); it opens centred again each time. The window is a transparent full-screen layer whose input region is just the frame, so clicks beside it reach the desktop, and a drag moves the frame at once.
- Laid out as the Windows 11 settings are: a search box ("Find a setting", focused on opening) centred at the very top, drawn as the Start menu's is (a pill, the same fill, outline and magnifier), with the close button at its right; below it, on the left, the title "Taskbar settings" and under it one item per page, one under the other; on the right the page's name as a heading above its fields. Pages: Taskbar (look, clock, workspace badge, auto-hide and its delays), Windows (grouping, previews and their options, new windows on their own workspace, Omarchy's dock) and Start menu. The current page has a mark and a tinted background. Typing in the search box replaces the page with a "Search results" heading and the matching fields of every page, each group named by its page: a field matches when every word typed is in its label, its hint or its page's name, in any case. No match says so. Choosing a page clears the search; Escape clears it first and closes the window the second time. A field that follows another setting (a delay with auto-hide off, a preview option with previews off, bar opacity with a transparent bar, the Start button's fields with no Start button) is indented under it and dimmed and inert while that setting says no. Each field is a switch, choice buttons, a stepper, a slider, a text field or a list editor. A test keeps the fields in step with the keys the configuration understands.
- A page with more fields than fit scrolls (wheel, or drag the thumb or click the track of its scroll bar): a thin track runs down the window's right edge with a thumb as long as the visible share of the page, shown only while there is something to scroll to. The room for it is always kept, so a page's layout does not change with the bar.
- Every change is written immediately, so the Dock updates live. Text fields commit on Enter or when focus leaves; the opacity slider writes once, on release.
- Places: unset means the Start menu's XDG folders; "Customize" seeds an editable list from them and "Use defaults" removes the key again.
- "Reset to defaults" (two clicks, to confirm) removes every setting in the window. Pins, their positions, Start Pins and recent Apps are not settings and are untouched.
- Not in the window: Pins and Placed positions (managed on the Dock itself), Start Pins and recent Apps (managed in the Start menu).

## Out of scope

- A floating dock style ([ADR 0002](adr/0002-startbar-is-only-a-taskbar.md)), a pinned-only launcher mode, minimise on a second click.
- A right edge, and enabling the Dock on some monitors only.
- In the Start menu: pin folders, Uninstall, web search results and recent files (there is no index of them to read).

Candidates for later releases, and ideas considered and set aside, are in [IDEAS.md](IDEAS.md).

## Verification

The pure JavaScript modules (ordering, Pins, Placed, configuration, the Start menu's rules, the reveal, preview and drag rules) are covered by `npm test`. Everything that depends on Quickshell or Hyprland is checked by hand with the checklist in [CONTRIBUTING.md](../CONTRIBUTING.md), on a two-monitor Omarchy machine.
