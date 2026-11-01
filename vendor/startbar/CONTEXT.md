# StartBar

A plugin for the Omarchy shell: a taskbar that gives mouse-driven access to every open window on every workspace and monitor and to pinned apps, with a Start menu for launching everything else.

## Language

**StartBar**:
The plugin's name, as users see it. It is not a part of the plugin: the panel is the Dock.
_Avoid_: using StartBar for the panel or the Start menu

**Dock**:
The bar along an edge of a monitor (the bottom, or with `position` the top, left or right) that holds Items, with a Start button at its start (the left end, or the top of the column on a side edge) and an optional clock at its end. On the bottom and top it is full-width. Every monitor gets its own Dock, and each Dock shows the same Items. It is always visible unless auto-hide is on, when it is Hidden or Revealed. Users know it as the taskbar.
_Avoid_: panel; a bare "bar" where it could be read as the Omarchy bar at the top of the screen

**Item**:
One slot in the Dock. An Item is either a Window Item or a Pin.
_Avoid_: icon (an icon is what an Item displays), entry, button

**Window**:
A single top-level window managed by Hyprland, on any workspace of any monitor. Each Window is represented by exactly one Window Item.
_Avoid_: client, toplevel, application (a Window belongs to an App; the two are different)

**Group Item**:
With `groupWindows` on, the single Item that stands for all of an App's Windows when there are two or more. It shows the icon with the edges of the others stacked behind it. It replaces that App's Window Items, so "one Window Item per Window" holds only while grouping is off. Hovering it previews every Window in the group.
_Avoid_: stack, bundle, combined icon

**Peek**:
Hovering a preview thumbnail to see its Window: the Window is focused for as long as the pointer is on it, then the previous focus, workspaces and maximized state are put back. Clicking the thumbnail keeps the Window focused instead.
_Avoid_: hover focus, preview focus

**App**:
The desktop entry that identifies which program a Window belongs to. An App supplies the icon and the launch command.
_Avoid_: application, program, class

**Pin**:
An App the user has chosen to keep in the Dock whether or not it currently has any Windows. A Pin holds a slot: while its App has Windows, their Window Items occupy that slot; when the last one closes, the Pin itself is shown and clicking it launches the App. A Pin is removed by Unpin in the Item's menu or by dragging the Item out of the Dock.
_Avoid_: favourite, shortcut, bookmark, dock entry; "pin" alone for a Start Pin

**Active Window**:
The Window that currently has keyboard focus. Its Window Item is highlighted.
_Avoid_: focused window, current window

**Attention**:
The state of a Window that has asked for the user's attention. Its Window Item is tinted with the theme's urgent colour; the Dock does not reveal itself for it.
_Avoid_: urgent, alert, bounce

**Letter Tile**:
The fallback shown for a Window whose App cannot be identified: the first letter of the window class in a themed square. Also shown, with the first letter of the App's name, while an App's icon file is not found.
_Avoid_: placeholder, generic icon, missing icon

**Launch Order**:
The order in which Windows appeared, except that a new Window joins the Window Items of its own App rather than going to the end. It is the Dock's default ordering rule for Window Items that the user has not Placed.
_Avoid_: creation order, open order, z-order

**Placed**:
An Item the user has dragged to a position of their choosing. A Placed Pin keeps its position permanently; a Placed Window Item keeps it until the Window closes, and a Placed Group Item until the App's last Window closes.
_Avoid_: reordered, moved, custom order

**Preview**:
The live thumbnail of a Window, with its title and a close button, shown while the pointer is on its Window Item.
_Avoid_: thumbnail (that is the picture inside a Preview), popup, peek

**Item menu**:
The menu opened by a right click on an Item: pinning, the App's own actions, the Window's state, and Close.
_Avoid_: context menu, window menu

**Preview menu**:
The menu opened by a right click on one Window's thumbnail in a Preview: that Window's state rows and Close Window. Its bottom-left corner is at the pointer.
_Avoid_: thumbnail menu, window menu

**Bar menu**:
The menu opened by a right click on the Dock away from any Item. It holds the common settings and the way into the settings window.
_Avoid_: quick menu, settings menu

## Start menu

**Start button**:
The button at the start of the Dock's Items. It opens the Start menu, or runs a command the user has chosen instead.
_Avoid_: launcher button, grid button (the grid is only its default icon)

**Start menu**:
StartBar's own menu, rising from the Start button: search, Start Pins, every App, Recommended and Places.
_Avoid_: launcher, app menu, Omarchy menu (that is a different menu, which the Start button can be set to open instead)

**Start Pin**:
An App the user keeps in the Start menu's Pinned grid. Start Pins are a separate list from the Dock's Pins, in the user's own order; until the user first changes the list, it mirrors the Pins.
_Avoid_: Pin (a Pin lives in the Dock), favourite, tile

**Recommended**:
The Apps most recently launched, from the Start menu or any other way (a window of the App opening is what counts).
_Avoid_: recents, history, frequent

**Places**:
The folders listed down the side of the Start menu. Clicking one opens it in the file manager.
_Avoid_: shortcuts, bookmarks, folders

**Hover mode**:
The state of a Start menu that was opened by resting the pointer on the Start button and has not been used yet. It closes by itself once the pointer has left; typing or clicking its search box ends hover mode and the menu then stays until dismissed.
_Avoid_: preview mode, peek, temporary menu

## Dock states

**Revealed**:
The Dock is visible. It floats over windows and never reserves screen space. It is always Revealed unless auto-hide is on.

**Hidden**:
The Dock is off screen. It only happens when auto-hide is on (off by default); the Dock becomes Revealed when the pointer rests on the Reveal Strip and returns to Hidden once the pointer has left the Dock.
_Avoid_: collapsed, minimised, auto-hidden (auto-hide is the behaviour, Hidden is the state)

**Reveal Strip**:
The invisible band along the full edge of a monitor the Dock sits on (the bottom, or the top, left or right with `position`), clear of any space the Omarchy bar reserves, that turns a Hidden Dock into a Revealed one. It exists only when auto-hide is on.
_Avoid_: hot zone, trigger area, edge
