<p align="center">
  <picture>
    <img alt="A tour of StartBar: a preview of a group of windows, an icon's right-click menu, launching an app from the Start menu, the bar's menu with a submenu, the settings window with search and the bar following the colours and edge chosen there, and the Dock on the left in the light colours" src="screenshots/hero.avif" width="100%" />
  </picture>
</p>

<h1 align="center">StartBar</h1>

<p align="center">
  <b>A taskbar with a Start menu for Omarchy.</b><br>
  Every open window on every workspace and monitor, your pinned apps, and a Start menu
  with search, all a click away.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#tour">Tour</a> ·
  <a href="#configure">Configure</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#update-and-remove">Update and remove</a> ·
  <a href="#contributing">Contributing</a>
</p>

> **Omarchy 4.5:** StartBar is compatible with the windowed mode coming in Omarchy 4.5.

## Install

```sh
omarchy plugin add https://github.com/bmaltais/StartBar --enable
```

It shows a taskbar along the bottom of every monitor, or any other edge you choose (top, left or right). Everything it needs comes with Omarchy; there is nothing else to install. The Start button opens StartBar's own Start menu. To open the Omarchy menu instead, right-click the bar, open **Start button** and choose **Open the Omarchy menu**.

## Tour

### The taskbar

<img src="screenshots/taskbar-clip.avif" alt="The taskbar with a Start button, pinned apps and open windows: the pointer goes over the icons, and resting on a group of two windows shows a live preview of each, with a thumbnail peeked" width="640">

- **Every window.** One icon per open window, across all workspaces and monitors. Click to jump to it.
- **Pins.** Keep apps in the bar whether or not they are running. Drag to reorder, drag out to unpin.
- **Grouped windows.** Optionally stack an app's windows into one icon and pick the window from the previews, as on Windows.
- **Any edge.** Put the bar at the bottom (the default), top, left or right of the screen. On the left and right it is a column, with the running dots beside the icons, above them on the top bar and below them on the bottom one. Menus and previews open on the side facing into the screen, the same distance from the bar as the Start menu is from the edge, as on Windows 11. Choose **Position** in the right-click menu or the settings window.
- **Extras.** Auto-hide, a clock, a workspace badge over each icon, a transparent bar, an option to reserve the bar's space so maximized windows stop at it, and an option to open each new window on a workspace of its own.

### The Start menu

<img src="screenshots/start-menu-clip.avif" alt="The Start menu opening from the Start button with pinned apps, recommended apps and folders; typing filters every installed app, the arrow keys move, Escape backs out, and All apps lists them A to Z" width="640">

Search every installed app, a Pinned grid you can reorder, an A-Z list, recently launched apps, your folders, and lock, sign out and power. Bind a key to toggle it, then type to search, use the arrow keys to move and Enter to launch. Escape backs out one step at a time.

### Hover previews

<img src="screenshots/preview.png" alt="Hovering a grouped icon shows one thumbnail per window to pick from" width="473">

Live window thumbnails with a close button. Hovering one shows that window, even from behind a maximized one, and moving away puts things back.

### Colours

<table>
  <tr>
    <th>Light</th>
    <th>Dark</th>
  </tr>
  <tr valign="top">
    <td><img src="screenshots/start-menu-light.png" alt="The taskbar and Start menu with the fixed light colours"></td>
    <td><img src="screenshots/start-menu-dark.png" alt="The taskbar and Start menu with the fixed dark colours"></td>
  </tr>
</table>

Colours and fonts follow the current Omarchy theme live, or pick a fixed light or dark bar.

### Right-click an icon

Each icon has its own menu. A pin with no windows offers the app's actions, the app itself and **Unpin from taskbar**; a running app adds its window actions (Maximize, Full screen, Float, Move to scratchpad), then the app and **Pin to taskbar**, and ends with **Close window** (**Close all windows** for a stack of several).

<img src="screenshots/icon-menu-clip.avif" alt="The menu of a running app that is not pinned, with its window actions, Close window, the app and Pin to taskbar, then the menu of a pinned app that is not running, with the app's actions, the app and Unpin from taskbar" width="640">

## Configure

Changes apply as you make them. There are two ways in.

### Right-click the bar

The common options, kept short: icon alignment, position (bottom, top, left or right), colours, the Start button and window previews open a submenu beside them, and the everyday toggles (auto-hide, clock, group windows, workspace badge, transparent background) sit below. Options that mean nothing while another is off are dimmed. The last row, **Settings…**, opens the full window.

<img src="screenshots/bar-menu-clip.avif" alt="The bar's right-click menu: the pointer goes down its rows, and Icon alignment, Position, Colors, Start button and Window previews each open a submenu beside them" width="640">

### The settings window

A control for every option, laid out like the Windows 11 settings: a search box at the top, the pages down the left (Taskbar, Windows, Start menu) and the chosen page on the right. Drag the title bar to move it. Options that follow another one are indented and dimmed while it is off.

<img src="screenshots/settings-clip.avif" alt="The settings window: the Taskbar, Windows and Start menu pages, a search for icon listing the matching settings from every page, and the clock switched on and off" width="640">

Type in the search box to find a setting on any page: every word must appear in a setting's name or description, or in its page's name.

### shell.json

Everything is saved in StartBar's own entry in `~/.config/omarchy/shell.json`, which you can also edit by hand:

```json
{
  "plugins": [
    {
      "id": "io.github.bmaltais.startbar",
      "alignment": "center",
      "position": "left",
      "startCommand": "builtin"
    }
  ]
}
```

Every key, its default, and how pinning and dragging behave are in [docs/SETTINGS.md](docs/SETTINGS.md).

## Commands

Run these with `omarchy-shell io.github.bmaltais.startbar <command>`, for instance from a key binding:

| Command | Does |
|---|---|
| `startMenu` | Toggles the Start menu on the focused monitor |
| `closeStartMenu` | Closes it |
| `settings` | Opens the settings window on the focused monitor |
| `closeSettings` | Closes it |

## Update and remove

```sh
omarchy plugin update io.github.bmaltais.startbar --yes && omarchy restart shell
```

Your settings and pins are kept, since they live in `shell.json` and not in the plugin folder. See the [releases page](https://github.com/bmaltais/StartBar/releases) for what changed.

```sh
omarchy plugin remove io.github.bmaltais.startbar
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development install, the tests and the manual checklist, [docs/testing.md](docs/testing.md) for the test session that runs the plugin in a second desktop your mouse and keyboard cannot reach, and [docs/recording-tours.md](docs/recording-tours.md) for how the animations above are recorded.

## License

MIT
