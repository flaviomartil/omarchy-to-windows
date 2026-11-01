# StartBar: ideas

What to build next. [SPEC.md](SPEC.md) is what the plugin does today. Vocabulary is in [CONTEXT.md](../CONTEXT.md). Decisions already taken are in [adr/](adr/).

An idea stays in the queue until it has a GitHub issue. Write the issue number in the table when you open it. When the behaviour ships, describe it in the spec, then delete the row here.

Status is `next` (do these first), `later`, or `declined`.

## Queue

| Idea | Status | Issue |
| --- | --- | --- |
| [Focus an App that already has Windows](#focus-an-app-that-already-has-windows) | next | |
| [Recommended: hide it, and count Dock launches](#recommended-hide-it-and-count-dock-launches) | next | |
| [Clock updates on the minute](#clock-updates-on-the-minute) | next | |
| [Compact Start menu, and All apps by category](#compact-start-menu-and-all-apps-by-category) | later | |
| [Optional combined Items](#optional-combined-items) | later | |
| [Skip the reveal slide](#skip-the-reveal-slide) | later | |

The three `next` rows stay inside the Start menu and the clock. [scripts/smoke.sh](../scripts/smoke.sh) already screenshots the Dock, the Start menu and the settings window. The `later` rows change the Dock model or the All apps catalog.

## Next

### Focus an App that already has Windows

The Dock already focuses a Window on left click, and middle-click launches a new instance. The Start menu always launches. `StartMenu.launchApp` emits a launch, and `Service.qml` `launchApp` calls `app.execute()`. Searching for an App that is already open starts another process. Recommended then records that launch.

In search results, Start Pins and Recommended, focus an existing Window of that App. One Window focuses immediately. Several Windows list that App's Windows by title, and the chosen row focuses that Window. Keep launching a new instance as a second action, the same meaning middle-click has on an Item.

Touches `StartMenu.js` (`launchApp` and the app overlay), `StartMenuView.qml`, and `Service.qml` (`launchApp`, `focusWindow`). The Dock model already knows which Windows belong to which App.

### Recommended: hide it, and count Dock launches

Recommended is the last six Apps launched from the Start menu (`MAX_RECENT_APPS` in `DockConfig.js`, `pushRecentApp` only on a menu launch). A Pin clicked on the Dock never enters the list, so the section is often empty. [CONTEXT.md](../CONTEXT.md) defines it that way. Places is the only section that can be hidden (`startPlaces: []`).

Add a setting to hide Recommended. While it is shown, record launches from Dock Pins as well as from the menu, still capped at six. That changes the glossary definition, so update [CONTEXT.md](../CONTEXT.md) and the spec in the same change. A rank over recently focused Windows is a different list and can wait.

### Clock updates on the minute

The clock draws the time and the date (`Locale.ShortFormat`) and refreshes on a 15-second timer (`clockTimer` in `Service.qml`). A new minute can show up late. Arm the timer for the next minute.

## Later

### Compact Start menu, and All apps by category

The menu is one shape. Width is `Style.space(600)` plus 150px when Places is showing. Height follows the screen and caps near `Style.space(640)`. Pinned is six columns (`PINNED_COLUMNS`) and Recommended is two (`RECENT_COLUMNS`). All apps is one A–Z list with the letter jump. The catalog keeps `id`, `name`, `genericName`, `keywords` and `noDisplay`. The desktop entry itself is on the flattened App as `entry`, and categories are not passed into `catalog`.

A compact preset (fewer columns, shorter height, Recommended hidden) comes before a free resize. A second All apps grouping reads categories from the desktop entry the menu already holds. User-made pages (a saved list in the shape of `startPins`) wait until that view has been used.

### Optional combined Items

The Dock shows one Window Item per Window. A new Window joins the Items of its own App, and a Pin holds that slot. When the row overflows, icons shrink until every Item fits.

Add an optional combined Item: one slot per App, and a flyout of its Windows that focuses the chosen one. Off by default, so one Item per Window stays the behaviour in the spec. Labels on Items wait. They need a wider row than shrink-to-fit allows.

### Skip the reveal slide

With auto-hide on, the Dock slides over `slideDurationMs` (150) with an in-out cubic ease (`Service.qml`). Add a setting to show and hide it with no animation.

## Declined

Anything under [SPEC.md](SPEC.md) "Out of scope" stays declined, including the floating frame in [ADR 0002](adr/0002-startbar-is-only-a-taskbar.md). Reopen one by changing that decision first. Shipped behaviour stays in the spec. Do not re-file it here.

These are declined only here:

| Idea | Standing decision |
| --- | --- |
| Tray, widgets, battery, network, a touch spacing mode | The Omarchy bar is at the top of the screen. The Dock's status is the optional clock. |
| A skin format, acrylic, or a private accent | Colours and fonts follow the Omarchy theme. The spec's `colorScheme`, opacity, `transparent` and `startIcon` are the look controls. |
| A matrix of click and modifier actions | Left click focuses or launches, middle click launches a new instance, right click opens the Item menu or the Bar menu. The Start button runs one command. |
| A backup button | The plugin's entry in `~/.config/omarchy/shell.json` is the backup, including Pins, Placed Pin positions, Start Pins and recent Apps. |
| Suggestions from a local model | Recommended can rank launches the plugin already stores. |
