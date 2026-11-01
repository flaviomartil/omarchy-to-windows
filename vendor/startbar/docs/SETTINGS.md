# StartBar settings and behaviour

The full reference. Capitalised terms (Dock, Item, Pin, Placed...) are defined in [CONTEXT.md](../CONTEXT.md). Most of this can be changed from the settings window, so you rarely need to edit the file by hand.

## Settings

All settings are stored (along with Pins and Placed Pin positions) in the Dock's own entry in Omarchy's shell config, `~/.config/omarchy/shell.json`, under `plugins[]`. Edit the entry by hand and the Dock picks it up live, no restart needed. Every setting can also be changed from the settings window (below), so you rarely need to edit the file.

### The bar

The Dock is a Windows 11-style bar along the bottom edge of every monitor.

```json
{
  "plugins": [
    {
      "id": "io.github.bmaltais.startbar",
      "alignment": "left",
      "autoHide": true,
      "startCommand": "builtin"
    }
  ]
}
```

| Key | Default | Description |
| --- | --- | --- |
| `alignment` | `left` | `left` or `center` for the Start button and icons |
| `position` | `bottom` | `bottom`, `top`, `left` or `right`: the screen edge the bar sits on |
| `autoHide` | `false` | Hide the bar until the pointer rests on the bar's screen edge |
| `reserveSpace` | `false` | With auto-hide off: windows (maximized ones included) stop at the Dock instead of running under it |
| `revealDelayMs` | `200` | With auto-hide: how long the pointer must rest on the Reveal Strip before the bar shows, in ms |
| `hideDelayMs` | `300` | With auto-hide: how long after the pointer leaves the bar before it hides, in ms |
| `iconSize` | `48` | Largest icon size in px; icons are also limited to `barHeight - 20` and shrink further to fit when there are many windows |
| `showWorkspaceBadge` | `false` | Workspace number or name over each window's icon |
| `groupWindows` | `true` | One stacked icon per app with two or more windows; hover it to pick a window from the previews |
| `barHeight` | `48` | Bar height in px |
| `edgeSpacing` | `12` | Space in px at the start of the bar before the Start button, and between the bar and the menus and previews that rise from it (the Start menu's side margin matches it) |
| `opacity` | `0.9` | Bar background opacity, 0 to 1 (at most 0.35 while Omarchy's bar is Glassy) |
| `transparent` | `false` | No bar background, icons only |
| `colorScheme` | `theme` | `theme` (follow Omarchy), `dark` or `light`; applies to the bar, the Start menu, the menus and the previews |
| `showStart` | `true` | Show the Start button |
| `startCommand` | `builtin` | What the Start button runs; `builtin` opens the built-in Start menu, `omarchy-menu toggle apps` the Omarchy menu |
| `startHoverOpen` | `false` | With the built-in menu, resting the pointer on the Start button opens it after a moment; it closes when you leave; typing (or clicking its search box) keeps it open; moving to another icon closes it |
| `startIcon` | `grid` | `grid` (drawn in QML), `omarchy`, `arch`, `linux`, an icon-theme name, or an absolute image path |
| `showClock` | `false` | Clock at the right end |
| `hideOmarchyDock` | `true` | Turn off Omarchy's own dock (the `omarchy.dock` plugin, shown on floating workspaces). Switching it on disables the plugin and switching it off enables it again; while it is off, a dock you disabled yourself stays disabled |
| `newWindowWorkspace` | `off` | `off`, `normal`, `maximized` or `fullscreen`. Otherwise a Window that opens tiled beside other Windows moves to the lowest-numbered empty workspace and is shown that way there (`normal` leaves its state alone). Floating Windows Omarchy did not float itself, and full screen ones, are left alone. A leftover `true` reads as `maximized` |
| `showPreviews` | `true` | Hover thumbnails with a close button |
| `previewSlide` | `true` | The hover preview rises out of the Dock edge when it appears; it still disappears at once |
| `previewPeek` | `true` | Hovering a preview thumbnail focuses that window to show it (switching workspace if needed); a maximized or full-screen window covering it is un-maximized for the peek; moving away restores the focus, workspaces and maximized state; clicking keeps it |
| `previewWarpPointer` | `true` | Clicking a preview also moves the pointer to the middle of that window |

Any numeric value that's missing or not a usable positive number falls back to its default. A `"style"` key left over from versions before 1.1.0 is ignored.

### Start menu

With `"startCommand": "builtin"`, the default, the Start button opens a menu anchored right above it (the Omarchy menu always centres on screen and can't be anchored):

- Opens on a click, or by resting the pointer on the Start button (`startHoverOpen`); a hover-opened menu goes away when you move off it, until you start typing or click its search box, which keeps it open. Clicking the grid icon doesn't keep it, and moving on to another icon closes it so that icon's preview shows.
- **Search** at the top: type to filter every installed app; Up/Down and Enter launch; Escape backs out one layer at a time.
- **Pinned**: a six-column grid. Right-click any app to **Pin to Start** or **Unpin from Start** (or pin it to the Dock). Until you change it, it shows your Dock Pins.
- **All apps ›**: an A-Z list with letter headings.
- **Recommended**: the last six apps launched from the menu.
- **Places** (left column): Home and your Documents, Downloads, Pictures, Music and Videos folders, from `~/.config/user-dirs.dirs`. One click opens a folder in your file manager.
- **Keyboard**: bind a key (say Super) to `omarchy-shell io.github.bmaltais.startbar startMenu` to toggle the menu. With nothing typed, the arrow keys walk Pinned then Recommended and Enter launches; in All apps, Up/Down walk the list. Click a letter heading in All apps for an A-Z jump grid.
- **Reorder pins**: drag a pinned app to a new slot.
- **Settings** (bottom of the Places column): opens Omarchy's setup menu.
- **Account and power** (bottom): your name and `~/.face` picture; click them for Lock and Sign out; the power button has Sleep, Restart and Shut down.

It is the one part of the Dock that takes keyboard focus, and only while open.

| Key | Default | Description |
| --- | --- | --- |
| `startPins` | the Dock's Pins | App ids pinned in the menu |
| `recentApps` | `[]` | Maintained automatically |
| `startPlaces` | XDG folders | List of paths (`~` allowed) replacing the Places column; `[]` hides it |

### Settings window

Right-click an empty part of the bar and choose **Settings…** (or run `omarchy-shell io.github.bmaltais.startbar settings`, handy for a keybinding) to open a window with a widget for every option in the tables above, with pages listed down the left (Taskbar, Windows, Start menu), a search box centred at the top to find a setting by typing, and options that depend on another one dimmed while it is off: switches, choice buttons, steppers, a slider for opacity, text fields, and an editor for the Start menu's Places folders. Changes apply instantly and are saved to `shell.json`. "Reset to defaults" (click twice) puts every setting back; your Pins and Start menu pins are kept.

### Menus

- **Right-click an icon**: Pin/Unpin, New Window and the app's own actions; for a window, Maximize/Restore, Full screen/Exit full screen, Float/Tile, and when floating Center and Pin on top; Move to scratchpad; then the app and Pin/Unpin; and last, Close window (Close all windows for a group). The menu stays open until you pick a row, click outside it, or move the pointer off it.
- **Right-click the bar** (an empty part) opens a short menu: Icon alignment, Position, Colors, Start button and Window previews are sections that open a submenu beside them, and the everyday toggles follow (auto-hide, clock, group windows, workspace badge, transparent background). Its last row, **Settings…**, opens the full settings window.

## Pinning

Right-click any Item and choose **Pin** to keep its App in the Dock whether or not it has open Windows; choose **Unpin** to drop it. A Pin with no Windows launches its App on left click. While its App has open Windows, they occupy the Pin's slot instead of showing a separate icon, so a pinned App never appears twice. Pin is disabled for a Letter Tile Item (an unresolvable App can't be pinned). You can also unpin by dragging the Item out of the Dock — see below.

Pins persist across restarts in the shell config above (the `pins` array on the Dock's entry, in order).

## Drag behaviour

- **Drag within the Dock** reorders Items: the Items in between step aside to show where it would land, and the dragged one stops at the first or last slot. The dropped position becomes Placed: a Placed Pin keeps that position permanently; a Placed Window Item keeps it only until that Window closes, after which the Item falls back to Launch Order.
- Dragging one Window of a pinned App (when it has more than one open) moves only that Window; its siblings stay in the Pin's slot.
- **Drag an Item out of the Dock** (release outside its bounds): if the Item's App is pinned, this unpins it — the Windows remain as ordinary Window Items. If the Item is an unpinned Window Item, it snaps back to where it was.
- The Dock stays Revealed for the whole of a drag and starts its hide timer only after the drop.
