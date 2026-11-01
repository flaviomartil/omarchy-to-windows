// Dock service entry point (see docs/SPEC.md; vocabulary in CONTEXT.md).
// Owns one layer-shell panel per monitor, each drawing the same Items built
// by DockModel.buildDockItems from live Hyprland state, the Pins and this
// session's Placed positions, between the Start button and the clock. It
// also owns what rises from the Dock (Previews, the Item menu, the Bar
// menu, and the Start menu in StartMenuView.qml) and the settings window.
// The rules themselves live in the JS modules imported below.
import QtQuick
import QtQml.Models
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockConfig.js" as DockConfig
import "StartMenu.js" as StartMenu
import "DockInteraction.js" as DockInteraction
import "DockGeometry.js" as DockGeometry
import "DockPlacement.js" as DockPlacement
import "DockPreview.js" as DockPreview
import "DockHyprland.js" as DockHyprland

Item {
  id: root

  // Injected by omarchy-shell (the first-party/plugin service loader).
  property var shell: null

  // True for the whole of a drag, on any monitor (docs/SPEC.md "Input";
  // set/cleared around Service.qml's drag.onActiveChanged/finishDrag).
  // dockState.refresh() checks this and skips rebuilding dockState.items
  // while it holds: DockModel.buildDockItems always returns fresh Item
  // objects, so any refresh mid-drag — an unrelated Hyprland event fires
  // constantly on a real desktop — would make the Repeater tear down and
  // rebuild every delegate, destroying the very Item whose MouseArea is
  // driving the drag. finishDrag clears this before placeItem/unpinFromDrag
  // so the drop's own refresh (immediate for a Window Item, via the
  // settings write's reload for a Pin) is never the one that gets skipped.
  property bool dragInProgress: false

  // Icon size and auto-hide timing (SPEC.md "How the Dock behaves" and
  // "Configuration"): read from the Dock's own entry in the shell config
  // (dockSettings below) and defaulted by DockConfig when the entry has no
  // values, a value is missing, or a hand edit leaves one unusable.
  // hideDelayMs must comfortably exceed slideDurationMs: the pointer
  // crosses the sliver between the Reveal Strip and the risen Dock while
  // neither is hovered, and the hide timer must not win that race.
  readonly property int iconSize: dockSettings.iconSize
  readonly property int revealDelayMs: dockSettings.revealDelayMs
  readonly property int hideDelayMs: dockSettings.hideDelayMs
  readonly property int slideDurationMs: 150
  // Kept just thick enough to be reliably hoverable; the screen edge itself
  // stops the cursor, so the strip doesn't need real height to feel solid,
  // and staying thin keeps it from swallowing clicks meant for a maximized
  // window's bottom edge.
  readonly property int revealStripHeight: 4

  // The bar's own settings (docs/SPEC.md "The bar"). autoHide is off by
  // default; when on, the bar uses the Reveal Strip and Hidden/Revealed rules.
  readonly property var taskbar: dockSettings.taskbar
  readonly property bool autoHide: taskbar.autoHide
  // A fixed palette for colorScheme dark/light, null to follow the theme.
  readonly property var scheme: DockConfig.schemeColors(taskbar.colorScheme)
  readonly property color colBackground: scheme ? scheme.background : Color.background
  readonly property color colForeground: scheme ? scheme.foreground : Color.foreground
  readonly property color colMuted: scheme ? scheme.muted : Color.muted
  readonly property color colAccent: scheme ? scheme.accent : Color.accent
  readonly property color colBorder: scheme ? scheme.border : Color.muted
  // The same choice for what rises from the bar (the Start menu, the menus,
  // the hover previews and tooltips), which otherwise wear the theme's popup
  // colours.
  readonly property color colPopupBackground: scheme ? scheme.background : Color.popups.background
  readonly property color colPopupText: scheme ? scheme.foreground : Color.popups.text
  readonly property color colPopupBorder: scheme ? scheme.border : Color.popups.border

  // How every menu and window the plugin raises looks, after Windows 11:
  // rounded corners (never sharper than the Start menu's), a hairline edge in
  // the text colour instead of the theme's accent line, a quiet hover fill.
  // Style.cornerRadius follows Hyprland's rounding, often 0.
  readonly property int menuRadius: Math.max(Style.cornerRadius, Style.space(8))
  readonly property int menuRowRadius: Math.max(Style.cornerRadius, Style.space(4))
  readonly property int menuPad: Style.space(4)
  readonly property int menuRowHeight: Style.space(32)
  // A popup window is only as big as it is drawn, so its shadow needs room
  // of its own: the popups are this much larger on every side and the menu
  // is drawn inset, with the anchor moved out by the same amount.
  readonly property int menuShadow: Style.space(14)
  // Omarchy's Glassy bar (shell.json bar.background): the bar and the Start
  // menu turn see-through, and Hyprland blurs what is behind them
  // (DockHyprland.glassRule). The bar is as clear as Omarchy's own, 0.35 at
  // most. The menus, Previews and settings window stay solid: they are separate
  // surfaces Hyprland does not blur, so the Windows behind would show through.
  readonly property bool glassy: dockSettings.glassy
  readonly property color colHairline: Util.alpha(colPopupText, 0.12)
  readonly property color colRowHover: Util.alpha(colPopupText, 0.08)

  // Settings and Pins (docs/SPEC.md "Configuration"): read from the Dock's
  // own entry in the shell config's plugins[] array and written back
  // through shell.updateEntryInline, the write-back hook the shell gives
  // every plugin for its own entry (PluginShellApi.updateEntryInline).
  // This object is only the adapter around DockConfig.js, which owns the
  // keys and defaults: effectiveView turns the entry into the properties
  // below, and apply(intent) hands a named intent to DockConfig.applyIntent
  // and persists the next entry. updateEntryInline persists whatever object
  // it's given as the whole entry, so each intent folds onto the entry as
  // last read, or onto the entry an earlier intent in the same tick already
  // produced (pendingEntry) — the file hasn't been re-read by then, and
  // folding onto rawEntry again would lose the first change. pins re-triggers
  // dockState.refresh() on change (below) the same way a Hyprland event
  // does, so a hand edit to the Pins list applies live exactly like a hand
  // edit to a setting does.
  QtObject {
    id: dockSettings

    readonly property string pluginId: root.shell && root.shell.pluginId ? root.shell.pluginId : "io.github.bmaltais.startbar"
    property var rawEntry: null
    property var pendingEntry: null
    // False until shell.json has been read once; before that, values are the
    // defaults, and the settings window waits rather than show them.
    property bool loaded: false
    property int iconSize: DockConfig.DEFAULT_ICON_SIZE
    property int revealDelayMs: DockConfig.DEFAULT_REVEAL_DELAY_MS
    property int hideDelayMs: DockConfig.DEFAULT_HIDE_DELAY_MS
    property var pins: []
    property var taskbar: DockConfig.effectiveView(null).taskbar
    property bool glassy: false
    // A Placed Pin's own position (CONTEXT.md "Placed"), persisted here
    // the same way pins is. A Placed Window Item's lives only in
    // dockState.itemsState.windowPlacements — it has no business surviving a
    // restart — so it isn't part of this settings object at all.
    property var placements: []
    // The Start menu's own pinned list and recent apps, its custom Places
    // folders (null: the user's XDG folders), and every settings-window
    // field's current value.
    property var startPins: []
    property var recentApps: []
    property var startPlaces: null
    property var values: DockConfig.effectiveView(null).values

    onPinsChanged: dockState.refresh()
    onPlacementsChanged: dockState.refresh()
    // groupWindows changes the Items themselves; any other bar setting
    // leaves the signature unchanged, so refresh() drops it again.
    onTaskbarChanged: dockState.refresh()

    function applyShellConfig(shellConfig) {
      var entry = DockConfig.findPluginEntry(shellConfig, dockSettings.pluginId)
      var view = DockConfig.effectiveView(entry)
      dockSettings.rawEntry = entry
      dockSettings.pendingEntry = null
      dockSettings.iconSize = view.settings.iconSize
      dockSettings.revealDelayMs = view.settings.revealDelayMs
      dockSettings.hideDelayMs = view.settings.hideDelayMs
      dockSettings.taskbar = view.taskbar
      dockSettings.glassy = !!(shellConfig && shellConfig.bar && shellConfig.bar.background === "glassy")
      dockSettings.pins = view.pins
      dockSettings.placements = view.placements
      dockSettings.startPins = view.startPins
      dockSettings.recentApps = view.recentApps
      dockSettings.startPlaces = view.startPlaces
      dockSettings.values = view.values
      dockSettings.syncOmarchyDock(view.taskbar.hideOmarchyDock)
      dockSettings.loaded = true
    }

    // docs/SPEC.md "Omarchy dock": hideOmarchyDock (on by default) turns the omarchy.dock plugin
    // off and on through the shell. It acts on a change only (and on the first
    // read when hiding), so a dock disabled by hand stays so while the setting is off.
    property var omarchyDockHidden: null
    function syncOmarchyDock(hide) {
      var before = dockSettings.omarchyDockHidden
      dockSettings.omarchyDockHidden = hide
      if (before === hide || (before === null && !hide)) return
      Quickshell.execDetached(["omarchy-shell", "shell", "setPluginEnabled", "omarchy.dock", hide ? "false" : "true"])
    }

    function apply(intent) {
      if (!root.shell || typeof root.shell.updateEntryInline !== "function") return false
      var base = dockSettings.pendingEntry !== null ? dockSettings.pendingEntry : dockSettings.rawEntry
      var next = DockConfig.applyIntent(base, intent)
      dockSettings.pendingEntry = next
      var written = root.shell.updateEntryInline(dockSettings.pluginId, next)
      if (!written) dockSettings.pendingEntry = null
      return written
    }
  }

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false

    function parseText() {
      try {
        return JSON.parse(text() || "{}")
      } catch (e) {
        return null
      }
    }

    onLoaded: dockSettings.applyShellConfig(shellConfigFile.parseText())
    onLoadFailed: dockSettings.applyShellConfig(null)
    onFileChanged: reload()
  }

  // Tracks Launch Order across live IPC updates: each Window's opened-at
  // rank is assigned the first time its address is seen and kept for as
  // long as the Window stays open, so closing one Window never reshuffles
  // the others. Named dockState, not state — every Item already has a
  // built-in `state` property, which would silently shadow an id of that
  // name in any binding written inside an Item (Repeater, Row, ...).
  ListModel { id: dockItemKeys }

  QtObject {
    id: dockState

    // DockModel.refreshItems' state: Launch Order ranks, Windows held back
    // for a class, this session's Placed Window Items (CONTEXT.md "Placed")
    // and what the Dock last showed.
    property var itemsState: DockModel.newItemsState()
    property bool holding: false
    property var items: []
    // HyprlandToplevel by Window address, for the taskbar's hover previews
    // (the Wayland handle ScreencopyView captures hangs off it).
    property var toplevelByAddress: ({})
    // Window titles by address, kept apart from `items` so a title change
    // (a browser tab switching, say) updates tooltips and previews without
    // rebuilding the Items — see DockModel.refreshItems.
    property var titles: ({})

    function refresh() {
      if (root.dragInProgress) return

      var next = DockModel.refreshItems(dockState.itemsState, {
        toplevels: Hyprland.toplevels ? Hyprland.toplevels.values : [],
        now: Date.now(),
        pins: dockSettings.pins,
        pinPlacements: dockSettings.placements,
        grouped: !!(root.taskbar && root.taskbar.groupWindows),
        lookup: function (name) { return DesktopEntries.heuristicLookup(name) },
        byId: function (appId) { return DesktopEntries.byId(appId) },
      })
      dockState.itemsState = next.state
      dockState.holding = next.held
      dockState.toplevelByAddress = next.handles
      dockState.titles = next.titles
      if (!next.changed) return
      dockState.items = next.items
      dockState.syncItemModel(next.items)
    }

    // The Dock's Repeater runs over dockItemKeys, one row per Item key, and
    // each delegate looks its Item up in itemByKey. Replacing the Items
    // array instead would tear down and rebuild every delegate on any
    // reorder, so a drop made every icon flash as it loaded again. Here an
    // Item that stays keeps its delegate, and a reorder is a `move`
    // (DockModel.keyOps works out the steps).
    property var itemByKey: ({})

    function syncItemModel(next) {
      var byKey = {}
      var nextKeys = []
      for (let n = 0; n < next.length; n++) {
        byKey[next[n].key] = next[n]
        nextKeys.push(next[n].key)
      }
      var current = []
      for (let r = 0; r < dockItemKeys.count; r++) current.push(dockItemKeys.get(r).key)
      dockState.itemByKey = byKey
      var ops = DockModel.keyOps(current, nextKeys)
      for (let o = 0; o < ops.length; o++) {
        if (ops[o].op === "remove") dockItemKeys.remove(ops[o].at)
        else if (ops[o].op === "move") dockItemKeys.move(ops[o].from, ops[o].to, 1)
        else dockItemKeys.insert(ops[o].at, { key: ops[o].key })
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") Quickshell.execDetached(DockHyprland.glassRule())
      // An App started any other way (Super+Space, a Pin, a terminal) is
      // still a recently launched App: openwindow data is
      // "address,workspace,class,title".
      if (event.name === "openwindow") {
        let opened = DockModel.openedWindow(event.data)
        let app = opened.class ? root.resolveApp({ class: opened.class }) : null
        if (app && app.id) dockSettings.apply({ type: "pushRecentApp", appId: app.id })
        // docs/SPEC.md "New window workspace"
        if (root.taskbar && root.taskbar.newWindowWorkspace !== "off") {
          let command = DockHyprland.openOnOwnWorkspace(opened.address, root.taskbar.newWindowWorkspace)
          if (command) Quickshell.execDetached(command)
        }
      }
      dockState.refresh()
    }
  }

  // DesktopEntries scans .desktop files asynchronously in the background,
  // so the very first refresh() (Component.onCompleted, below) can run
  // before it has found any entries, resolving every already-open Window's
  // App to null. Without this, those Windows would be stuck showing a
  // blank Letter Tile forever, since nothing else re-resolves an Item once
  // built — Hyprland's own onRawEvent refresh happens to paper over this on
  // a busy desktop, but not on one sitting idle right after the Dock loads.
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { dockState.refresh() }
  }

  // A Window's `class` (used for both App resolution and the Letter Tile
  // fallback) comes from toplevel.lastIpcObject, which Quickshell only
  // populates from a Window's own "openwindow" IPC event — a Window
  // already open when this service starts (every Window, right after
  // enabling the Dock or restarting the shell) never gets that event
  // during this run, so its lastIpcObject stays `{}` forever and it
  // renders as a blank, letter-less square (confirmed on a machine with
  // no Windows opened since the last shell restart). Hyprland.refreshToplevels()
  // force-fetches the missing data via `hyprctl -j clients`.
  Component.onCompleted: {
    Quickshell.execDetached(DockHyprland.glassRule())
    // A peek the last shell never got to undo (it restarted mid-hover).
    root.peekRestore()
    Hyprland.refreshToplevels()
    dockState.refresh()
  }

  // refreshToplevels() is async with no completion signal of its own, and a
  // blind "wait a bit then refresh once" timer isn't reliable: confirmed on
  // this machine, a cold `hyprctl -j clients` fetch can take over a
  // second, so a fixed-delay timer fires before the data lands on a slow
  // boot, and nothing else was ever guaranteed to retry — every
  // already-open Window's tile stayed blank until some unrelated Hyprland
  // event happened to trigger a refresh. Confirmed via live logging on
  // this machine that Hyprland.toplevels gains its entries for these
  // Windows *before* their class does: each toplevel is added with an
  // empty lastIpcObject, which is then hydrated moments later in place.
  // So both edges matter — onObjectAdded covers a toplevel that (on some
  // runs) arrives already populated, and the per-toplevel
  // lastIpcObjectChanged watcher below covers the far more common case
  // here, where it arrives empty and is corrected right after.
  Instantiator {
    model: Hyprland.toplevels
    delegate: Item {
      id: hydrationWatcher
      required property var modelData

      Connections {
        target: hydrationWatcher.modelData
        function onLastIpcObjectChanged() { dockState.refresh() }
      }
    }
    onObjectAdded: function (index, object) { dockState.refresh() }
  }

  // The two hydration paths above only fire if `hyprctl -j clients` (the
  // fetch refreshToplevels() triggers) actually lands, and that isn't
  // guaranteed — confirmed live, more than once, on this machine: a
  // Window can sit with an empty class through dozens of unrelated
  // refresh() calls and 20+ seconds (once even 56+ seconds) without
  // either path ever firing for it. This isn't only a login-time thing
  // either — it's been seen for a Window opened minutes into an
  // already-running session, well past any fixed post-startup window.
  // So this polls dockState.items every second, for as long as the
  // service runs, and re-issues refreshToplevels() whenever a Window
  // Item is still sitting unresolved (no App, no Letter Tile letter).
  //
  // An earlier version tried to be clever and stop once nothing looked
  // unresolved, counting a fixed number of attempts after startup only —
  // confirmed live that this disarms itself on attempt 1, before the
  // stalled toplevel has even been added to Hyprland.toplevels (an empty
  // item list has nothing to find unresolved), and confirmed live again
  // that a stall can happen well after any such fixed window would have
  // expired. So this never stops, and only calls refreshToplevels() when
  // there's actually something to fix — a same-tick miss just costs one
  // more second before the next tick catches it, rather than losing the
  // safety net for good.
  Timer {
    interval: 1000
    repeat: true
    running: true

    onTriggered: {
      var unresolved = DockModel.awaitingToplevels(dockState.items, dockState.holding)
      if (unresolved) Hyprland.refreshToplevels()
      // The wait for a class ends by the clock, not by an event.
      if (dockState.holding) dockState.refresh()
    }
  }

  function resolveApp(window) {
    return DockModel.resolveApp(window.class, function (name) { return DesktopEntries.heuristicLookup(name) })
  }

  // App icons, for the Dock and the Start menu (IconResolver.qml): Qt's
  // lookup, then a search of the icon directories when Qt has cached a miss.
  IconResolver { id: iconResolver }
  property alias icons: iconResolver

  function iconSource(name) {
    return root.icons.source(name)
  }

  // The Letter Tile's letter for an App with no icon: its name's first letter.
  function appLetter(app) {
    return app && app.name ? app.name.charAt(0).toUpperCase() : ""
  }

  // A Pin resolves its own App directly by the id it was pinned under
  // (CONTEXT.md "Pin"), independent of any Window — unlike resolveApp,
  // which only ever has a window class to go on. A falsy return here is
  // exactly the "App is no longer installed" case (docs/SPEC.md "What the
  // Dock shows").
  function resolveAppById(appId) {
    return appId ? DesktopEntries.byId(appId) || null : null
  }

  // Everything that asks Hyprland for something is built in DockHyprland.js,
  // which returns the command to run; these only run it.
  function focusWindowAndWarp(address) {
    var command = DockHyprland.focusWindowAndWarp(address)
    if (command) Quickshell.execDetached(command)
  }

  function focusWindow(address) {
    var command = DockHyprland.focusWindow(address)
    if (command) Quickshell.execDetached(command)
  }

  function rescueWindows(addresses) {
    var command = DockHyprland.rescueWindows(addresses)
    if (command) Quickshell.execDetached(command)
  }

  // Left click on a Pin with no Windows launches its App (docs/SPEC.md
  // "Input"). A missing App's Pin has no `execute` to call — clicking it
  // is a no-op until Unpin, same as a Letter Tile Window Item is a no-op
  // to click on today.
  function launchApp(app) {
    if (!app || typeof app.execute !== "function") return
    app.execute()
  }

  // A Window-state row of the context menu (DockModel.windowActions has the
  // ids and labels, DockHyprland.windowAction the dispatch).
  function runWindowAction(id, address) {
    var command = DockHyprland.windowAction(id, address)
    if (command) Quickshell.execDetached(command)
  }

  // Close Window (docs/SPEC.md "Input", the context menu).
  function closeWindow(address) {
    var command = DockHyprland.closeWindow(address)
    if (command) Quickshell.execDetached(command)
  }

  // Pin/Unpin (docs/SPEC.md "Input", the context menu): DockConfig.applyIntent
  // computes the Pins list's new contents; this only hands the intent to
  // dockSettings.apply, the same write-back path a hand edit to Pins
  // already applies live through.
  function togglePin(appId, pinned) {
    if (!appId) return
    dockSettings.apply({ type: pinned ? "unpinApp" : "pinApp", appId: appId })
  }

  // Drag within the Dock (docs/SPEC.md "Input": "reorder"; CONTEXT.md
  // "Placed"): DockModel.movedPlacements works out every Placed position
  // after the drop. The Pins' are persisted through dockSettings.apply
  // exactly like Pin/Unpin already is, so they survive a restart; the Window
  // Items' go to dockState.itemsState (DockModel.dropPlaced does the split).
  function placeItem(item, targetIndex) {
    var dropped = DockModel.dropPlaced(dockState.itemsState, dockState.items, dockSettings.placements, item.key, targetIndex)
    dockState.itemsState = dropped.state
    // Shown now, not once the config file has been written and read back: the
    // Dock would otherwise sit in the old order for a moment after a drop.
    dockSettings.placements = dropped.pins
    dockSettings.apply({ type: "setPlacements", placements: dropped.pins })
    dockState.refresh()
  }

  // Drag out of the Dock, for an Item whose App is pinned (docs/SPEC.md
  // "Input": "Drag out of the Dock: unpin the Item's App if pinned"): one
  // intent so dropping the App from Pins and dropping its own Pin's Placed
  // position (CONTEXT.md "Placed") land in the same shellConfig update.
  // Dragging an unpinned Window Item out is a snap-back
  // (docs/SPEC.md "Input"): the Dock itself has nothing to persist for
  // that, so it never calls this at all.
  function unpinFromDrag(appId) {
    if (!appId) return
    dockSettings.apply({ type: "unpinAppFromDrag", appId: appId })
  }

  // A Pin whose App is installed shows no tooltip, as in Windows: its icon
  // says what it is. Only a missing one explains itself.
  function pinHasNoTooltip(item) {
    return item.kind === "pin" && !item.missing
  }

  // A missing Pin's tooltip (docs/SPEC.md "What the Dock shows": "a
  // 'missing' tooltip"): its bare Pin id and an explicit missing note.
  function pinTooltipText(item) {
    if (item.missing) return item.appId + " (missing)"
    return (item.app && item.app.name) || item.appId
  }

  // The Item's own App id for Pin/Unpin (docs/SPEC.md "Input"): a Pin's
  // own id directly, or a Window Item's resolved App id — DockModel.menuFor
  // already reports canPin false whenever a Window Item has none.
  function menuAppId(item) {
    return item.kind === "pin" ? item.appId : (item.app ? item.app.id : null)
  }

  // Peek (previewPeek): hovering a preview thumbnail focuses its Window to
  // show it, and leaving puts things back. The first peek saves the
  // focused Window and each monitor's workspace in a state file; peekRestore
  // replays it, peekCommit (a click picked the Window) throws it away.
  // DockPreview.js decides when each is asked for, DockHyprland.js builds them.
  //
  // Peek scripts run one at a time, in the order asked for (a plain
  // execDetached per script let a restore overtake a peek).
  property var peekQueue: []

  Process {
    id: peekRunner
    onExited: root.peekNext()
  }

  function peekRun(command) {
    root.peekQueue.push(command)
    if (!peekRunner.running) root.peekNext()
  }

  function peekNext() {
    if (root.peekQueue.length === 0) return
    peekRunner.command = root.peekQueue.shift()
    peekRunner.running = true
  }

  function peekWindow(address) {
    var command = DockHyprland.peekWindow(address)
    if (command) root.peekRun(command)
  }

  function peekRestore() {
    root.peekRun(DockHyprland.peekRestore())
  }

  function peekCommit() {
    root.peekRun(DockHyprland.peekCommit())
  }

  // Previews off: a click on a Group Item focuses the Window after the
  // Active one, wrapping round.
  function focusNextInGroup(item) {
    var windows = item.windows || []
    var at = -1
    for (let i = 0; i < windows.length; i++) if (windows[i].active) at = i
    var next = windows[(at + 1) % windows.length]
    if (next) root.focusWindow(next.id)
  }

  function windowTooltipText(item) {
    if (item.count > 1) {
      let name = (item.app && item.app.name) || item.window.class || ""
      return name + "\n" + item.count + " windows"
    }
    return (dockState.titles[item.window.id] || item.window.title || item.window.class || "") + "\nWorkspace: " + (item.badge || "")
  }

  // ---- Settings window (docs/SPEC.md "Settings window") -------------------
  // Opened by a right click on the bar, or with
  // `omarchy-shell io.github.bmaltais.startbar settings`. One window, shown on the monitor
  // that was clicked. DockConfig.settingsSchema() lists every option and its
  // widget; every change is written straight back through dockSettings.apply,
  // so the Dock updates live. Text fields commit when you press Enter or
  // click away.
  property var settingsScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

  // The monitor the keyboard/pointer focus is on, for opens that don't come
  // from a click on a particular monitor's bar.
  function focusedScreen() {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    for (let i = 0; i < Quickshell.screens.length; i++) {
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    }
    return null
  }

  // Asked (by IPC) to toggle or close the Start menu on one monitor; each
  // monitor's panel owns a menu and answers only for its own screen.
  signal startMenuRequested(string screenName, string action)

  function focusedScreenName() {
    var screen = root.focusedScreen()
    return screen ? screen.name : ""
  }

  function openSettings(screen) {
    var target = screen || root.focusedScreen()
    if (target) root.settingsScreen = target
    settingsWindow.wanted = true
  }

  IpcHandler {
    target: "io.github.bmaltais.startbar"
    function settings(): void { root.openSettings(null) }
    function closeSettings(): void { settingsWindow.wanted = false }
    // For a Super-key binding: `omarchy-shell io.github.bmaltais.startbar startMenu`.
    function startMenu(): void { root.startMenuRequested(root.focusedScreenName(), "toggle") }
    function closeStartMenu(): void { root.startMenuRequested(root.focusedScreenName(), "close") }
    // Where the Dock's Items and any open menu are on the focused monitor, as
    // JSON (see `layout` in the panel). For the scripts that drive the pointer.
    function layout(): string {
      var name = root.focusedScreenName()
      for (let i = 0; i < panels.instances.length; i++) {
        if (panels.instances[i].screen && panels.instances[i].screen.name === name) {
          return JSON.stringify(panels.instances[i].layout())
        }
      }
      return "{}"
    }
  }

  FileView {
    id: userDirsForSettings
    path: Quickshell.env("HOME") + "/.config/user-dirs.dirs"
    printErrors: false
  }

  PanelWindow {
    id: settingsWindow

    readonly property var values: dockSettings.values
    property bool confirmingReset: false
    // The page shown: an index into DockConfig.settingsSchema().
    property int page: 0
    // What is typed in the search box; while it is not blank the right side
    // lists the matching fields of every page instead of the chosen page.
    property string query: ""
    readonly property bool searching: settingsWindow.query.trim() !== ""
    readonly property var schema: DockConfig.settingsSchema()
    readonly property var shownGroups: settingsWindow.searching
      ? DockConfig.searchSettings(settingsWindow.schema, settingsWindow.query)
      : [settingsWindow.schema[settingsWindow.page]]

    // Asked to be open; shown only once the settings have been read, so the
    // fields never appear with defaults and then change.
    property bool wanted: false
    screen: root.settingsScreen
    visible: settingsWindow.wanted && dockSettings.loaded
    color: "transparent"
    WlrLayershell.namespace: "omarchy-startbar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // The window covers the whole screen, transparent, and only the frame
    // takes input (`mask`), so the clicks around it reach the desktop. The
    // frame sits at posX, posY inside it; dragging the title bar moves it
    // there at once, with no round trip to the compositor (moving a
    // layer-shell window by its margins lags the pointer and the drag
    // wobbles). It opens centred, on the screen it was opened from.
    readonly property real boxWidth: Style.space(780) + root.menuShadow * 2
    readonly property real boxHeight: Math.min(Style.space(620), (root.settingsScreen ? root.settingsScreen.height : 900) - Style.space(80)) + root.menuShadow * 2
    property real posX: 0
    property real posY: 0
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    mask: Region { item: settingsFrame }

    function centre() {
      var sw = root.settingsScreen ? root.settingsScreen.width : 1920
      var sh = root.settingsScreen ? root.settingsScreen.height : 1080
      settingsWindow.posX = Math.max(0, (sw - settingsWindow.boxWidth) / 2)
      settingsWindow.posY = Math.max(0, (sh - settingsWindow.boxHeight) / 2)
    }
    // Keeps the frame on the screen: at least the title bar stays reachable.
    function moveBy(dx, dy) {
      var sw = root.settingsScreen ? root.settingsScreen.width : 1920
      var sh = root.settingsScreen ? root.settingsScreen.height : 1080
      var grab = Style.space(60)
      settingsWindow.posX = Math.max(grab - settingsWindow.boxWidth, Math.min(sw - grab, settingsWindow.posX + dx))
      settingsWindow.posY = Math.max(-root.menuShadow, Math.min(sh - grab, settingsWindow.posY + dy))
    }

    onVisibleChanged: {
      if (visible) {
        settingsWindow.centre()
        settingsWindow.query = ""
        settingsSearch.forceActiveFocus()
      } else {
        settingsWindow.confirmingReset = false
      }
    }
    onPageChanged: settingsFlick.contentY = 0
    onQueryChanged: settingsFlick.contentY = 0

    function commit(key, value) {
      dockSettings.apply({ type: "setSetting", key: key, value: value })
    }

    // Every setting back to its default; Pins, their positions and the Start
    // menu's own pins and recents are left alone.
    function resetAll() {
      dockSettings.apply({ type: "resetSettings" })
    }

    Timer {
      id: resetConfirmTimer
      interval: 3000
      onTriggered: settingsWindow.confirmingReset = false
    }

    RectangularShadow {
      anchors.fill: settingsFrame
      radius: settingsFrame.radius
      blur: root.menuShadow
      offset.y: Style.space(4)
      color: Qt.rgba(0, 0, 0, 0.6)
    }

    Rectangle {
      id: settingsFrame
      x: settingsWindow.posX + root.menuShadow
      y: settingsWindow.posY + root.menuShadow
      width: settingsWindow.boxWidth - root.menuShadow * 2
      height: settingsWindow.boxHeight - root.menuShadow * 2
      radius: root.menuRadius
      color: root.colPopupBackground
      border.width: Style.normalBorderWidth
      border.color: root.colHairline
      focus: true
      // Escape clears a search first, then closes the window.
      Keys.onEscapePressed: {
        if (settingsWindow.searching) settingsWindow.query = ""
        else settingsWindow.wanted = false
      }

      // Header
      Item {
        id: settingsHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(60)

        // Drag the title bar to move the window. The window moves with the
        // pointer, so the pointer's place in it stays put and each move is
        // the distance from where the press was.
        MouseArea {
          anchors.fill: parent
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
          property real pressX: 0
          property real pressY: 0
          onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y }
          onPositionChanged: function (mouse) {
            if (pressed) settingsWindow.moveBy(mouse.x - pressX, mouse.y - pressY)
          }
        }

        // The search box, centred in the title bar, drawn like the Start
        // menu's: a pill with the same fill, outline, magnifier and shadow.
        RectangularShadow {
          anchors.fill: searchBox
          radius: searchBox.radius
          blur: Style.space(6)
          offset.y: Style.space(1)
          color: Qt.rgba(0, 0, 0, 0.22)
        }

        Rectangle {
          id: searchBox
          anchors.centerIn: parent
          width: Math.min(Style.space(380), parent.width - Style.space(120))
          height: Style.space(34)
          radius: height / 2
          // Opaque, so the shadow behind it does not show through the box.
          color: Qt.tint(root.colPopupBackground, Util.alpha(root.colPopupText, 0.05))
          border.width: 1
          border.color: Util.alpha(root.colPopupText, 0.12)

          Text {
            textFormat: Text.PlainText
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg + 2
            anchors.verticalCenter: parent.verticalCenter
            text: "\uDB80\uDF49"
            color: Util.alpha(root.colPopupText, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 4
          }

          Text {
            textFormat: Text.PlainText
            visible: settingsSearch.text === ""
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "Find a setting"
            color: Util.alpha(root.colPopupText, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          PlainField {
            id: settingsSearch
            anchors.fill: parent
            anchors.leftMargin: searchIcon.x + searchIcon.width + Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            maxLength: 64
            color: root.colPopupText
            fontFamily: Style.font.family
            fontPixelSize: Style.font.body
            text: settingsWindow.query
            onTextChanged: if (settingsWindow.query !== settingsSearch.text) settingsWindow.query = settingsSearch.text
          }

          // The query is also cleared by Escape, which lives outside the box.
          Connections {
            target: settingsWindow
            function onQueryChanged() { if (settingsSearch.text !== settingsWindow.query) settingsSearch.text = settingsWindow.query }
          }
        }

        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(30)
          height: width
          radius: root.menuRowRadius
          color: closeSettingsMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "✕"
            color: root.colPopupText
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: closeSettingsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsWindow.wanted = false
          }
        }
      }

      // Left side, as in the Windows 11 settings: one item per page, one
      // under the other.
      Item {
        id: settingsSide
        anchors.top: settingsHeader.bottom
        anchors.bottom: settingsFooter.top
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg
        width: Style.space(190)

        // The window's name, on the row of the page heading beside it.
        Text {
          textFormat: Text.PlainText
          id: settingsTitle
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(40)
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: "Taskbar settings"
          color: root.colPopupText
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 3
          font.bold: true
        }

        Column {
          anchors.top: settingsTitle.bottom
          anchors.topMargin: Style.spacing.sm
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(2)

          Repeater {
            model: settingsWindow.schema

            delegate: Rectangle {
              id: navItem
              required property var modelData
              required property int index
              readonly property bool current: !settingsWindow.searching && settingsWindow.page === navItem.index
              width: parent.width
              height: Style.space(38)
              radius: root.menuRowRadius
              color: navItem.current
                ? Util.alpha(root.colAccent, 0.22)
                : (navMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : "transparent")

              // The mark beside the current page.
              Rectangle {
                visible: navItem.current
                anchors.left: parent.left
                anchors.leftMargin: Style.space(3)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(3)
                height: Style.space(16)
                radius: width / 2
                color: root.colAccent
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: navItem.modelData.title
                color: root.colPopupText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: navItem.current
              }

              MouseArea {
                id: navMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  settingsWindow.query = ""
                  settingsWindow.page = navItem.index
                }
              }
            }
          }
        }
      }

      // The heading of the right side: the page, or what a search found.
      Text {
        textFormat: Text.PlainText
        id: settingsHeading
        anchors.top: settingsHeader.bottom
        anchors.left: settingsSide.right
        anchors.leftMargin: Style.spacing.lg * 2
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        height: Style.space(40)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: settingsWindow.searching ? "Search results" : settingsWindow.schema[settingsWindow.page].title
        color: root.colPopupText
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 8
        font.bold: true
      }

      // Body: scrolls when the screen is short.
      Flickable {
        id: settingsFlick
        anchors.top: settingsHeading.bottom
        anchors.bottom: settingsFooter.top
        anchors.left: settingsSide.right
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.lg * 2
        // Room for the scroll bar's gutter, always: sizing the body by whether
        // it scrolls would change its width, and with it its height.
        anchors.rightMargin: Style.spacing.lg + settingsScrollBar.gutter
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: settingsColumn
          width: settingsFlick.width
          spacing: Style.spacing.xs

          Text {
            textFormat: Text.PlainText
            visible: settingsWindow.searching && settingsWindow.shownGroups.length === 0
            width: settingsColumn.width
            wrapMode: Text.WordWrap
            topPadding: Style.spacing.md
            text: "No settings match \u201C" + settingsWindow.query.trim() + "\u201D."
            color: Util.alpha(root.colPopupText, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: settingsWindow.shownGroups

            delegate: Column {
              id: groupBlock
              required property var modelData
              required property int index
              width: settingsColumn.width

              // Search results come from several pages: say which.
              Text {
                textFormat: Text.PlainText
                visible: settingsWindow.searching
                topPadding: Style.spacing.md
                bottomPadding: Style.spacing.xs
                text: groupBlock.modelData.title
                color: Util.alpha(root.colPopupText, 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: groupBlock.modelData.fields

                delegate: Item {
                  id: fieldRow
                  required property var modelData
                  readonly property var field: fieldRow.modelData
                  readonly property var value: settingsWindow.values[fieldRow.field.key]
                  readonly property bool stacked: fieldRow.field.type === "list"
                  // A field that follows another setting is dimmed and
                  // inert while that one is off, and indented under it.
                  readonly property bool live: DockConfig.fieldEnabled(fieldRow.field, settingsWindow.values)
                  readonly property real indent: fieldRow.field.enabledWhen ? Style.space(16) : 0

                  width: groupBlock.width
                  opacity: fieldRow.live ? 1 : 0.4
                  height: fieldRow.stacked
                    ? labelColumn.implicitHeight + editorLoader.height + Style.spacing.md * 2
                    : Math.max(labelColumn.implicitHeight, editorLoader.height) + Style.spacing.md * 2

                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Util.alpha(root.colHairline, 0.5)
                  }

                  Column {
                    id: labelColumn
                    anchors.top: parent.top
                    anchors.topMargin: Style.spacing.md
                    anchors.left: parent.left
                    anchors.leftMargin: fieldRow.indent
                    width: (fieldRow.stacked ? parent.width : parent.width - editorLoader.width - Style.spacing.md) - fieldRow.indent

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: fieldRow.field.label
                      color: root.colPopupText
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: !!fieldRow.field.hint
                      width: parent.width
                      wrapMode: Text.WordWrap
                      text: fieldRow.field.hint || ""
                      color: Util.alpha(root.colPopupText, 0.55)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Loader {
                    id: editorLoader
                    enabled: fieldRow.live
                    anchors.right: parent.right
                    anchors.verticalCenter: fieldRow.stacked ? undefined : parent.verticalCenter
                    anchors.bottom: fieldRow.stacked ? parent.bottom : undefined
                    anchors.bottomMargin: fieldRow.stacked ? Style.spacing.md : 0
                    width: fieldRow.stacked ? parent.width : implicitWidth
                    sourceComponent: {
                      switch (fieldRow.field.type) {
                      case "bool": return switchEditor
                      case "choice": return choiceEditor
                      case "int": return stepperEditor
                      case "slider": return sliderEditor
                      case "text": return textEditor
                      case "list": return listEditor
                      }
                      return null
                    }
                    onLoaded: {
                      item.field = Qt.binding(function () { return fieldRow.field })
                      item.value = Qt.binding(function () { return fieldRow.value })
                    }

                    Connections {
                      target: editorLoader.item
                      ignoreUnknownSignals: true
                      function onCommit(next) { settingsWindow.commit(fieldRow.field.key, next) }
                    }
                  }
                }
              }
            }
          }

          Item { width: 1; height: Style.spacing.md }
        }
      }

      // A scroll bar for the body, there only while the page has more than
      // fits, so a page that scrolls is seen to: a track down the window's
      // right edge and a thumb as long as the visible share of the page. Drag
      // the thumb or click the track; the wheel scrolls the body itself.
      // (Hand-drawn like the rest of the window: no native controls.)
      Item {
        id: settingsScrollBar
        readonly property int gutter: Style.spacing.lg + Style.spacing.xs
        readonly property real extent: settingsFlick.contentHeight - settingsFlick.height
        visible: settingsScrollBar.extent > 1
        anchors.top: settingsFlick.top
        anchors.bottom: settingsFlick.bottom
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        width: Style.spacing.md

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Util.alpha(root.colPopupText, 0.08)
        }

        Rectangle {
          id: scrollThumb
          width: parent.width
          radius: width / 2
          height: Math.min(parent.height, Math.max(Style.space(28), parent.height * settingsFlick.height / settingsFlick.contentHeight))
          y: settingsScrollBar.extent > 0
            ? (parent.height - height) * settingsFlick.contentY / settingsScrollBar.extent : 0
          color: Util.alpha(root.colPopupText, scrollMouse.pressed ? 0.55 : (scrollMouse.containsMouse ? 0.4 : 0.28))
        }

        MouseArea {
          id: scrollMouse
          // A wider target than the thin bar.
          anchors.fill: parent
          anchors.leftMargin: -Style.spacing.sm
          anchors.rightMargin: -Style.spacing.lg
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor

          function scrollTo(pointerY) {
            var room = settingsScrollBar.height - scrollThumb.height
            if (room <= 0) return
            var top = Math.max(0, Math.min(pointerY - scrollThumb.height / 2, room))
            settingsFlick.contentY = top / room * settingsScrollBar.extent
          }
          onPressed: function (mouse) { scrollMouse.scrollTo(mouse.y) }
          onPositionChanged: function (mouse) { if (scrollMouse.pressed) scrollMouse.scrollTo(mouse.y) }
        }
      }

      // Footer
      Item {
        id: settingsFooter
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(52)

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: "Changes apply instantly"
          color: Util.alpha(root.colPopupText, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          width: resetLabel.implicitWidth + Style.spacing.lg * 2
          height: Style.space(32)
          radius: root.menuRowRadius
          color: settingsWindow.confirmingReset
            ? Util.alpha(Color.urgent, 0.5)
            : (resetMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : Util.alpha(root.colPopupText, 0.08))

          Text {
            textFormat: Text.PlainText
            id: resetLabel
            anchors.centerIn: parent
            text: settingsWindow.confirmingReset ? "Click again to reset everything" : "Reset to defaults"
            color: root.colPopupText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (settingsWindow.confirmingReset) {
                settingsWindow.confirmingReset = false
                resetConfirmTimer.stop()
                settingsWindow.resetAll()
              } else {
                settingsWindow.confirmingReset = true
                resetConfirmTimer.restart()
              }
            }
          }
        }
      }
    }

    // --- Editors: each is given `field` and `value` and emits commit(next).

    Component {
      id: switchEditor
      Rectangle {
        id: sw
        property var field: null
        property var value: false
        signal commit(var next)
        implicitWidth: Style.space(42)
        implicitHeight: Style.space(24)
        width: implicitWidth
        height: implicitHeight
        radius: height / 2
        color: sw.value ? root.colAccent : Util.alpha(root.colPopupText, 0.25)
        // The Loader hands over the real value just after this is created;
        // animating only once that has settled keeps the knob from sliding
        // into place when the window opens.
        property bool settled: false
        Component.onCompleted: Qt.callLater(function () { sw.settled = true })

        Rectangle {
          width: parent.height - 6
          height: width
          radius: width / 2
          y: 3
          x: sw.value ? parent.width - width - 3 : 3
          color: root.colPopupBackground

          Behavior on x { enabled: sw.settled; NumberAnimation { duration: 100 } }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: sw.commit(!sw.value)
        }
      }
    }

    Component {
      id: choiceEditor
      Row {
        id: choices
        property var field: null
        property var value: ""
        signal commit(var next)
        spacing: 2

        Repeater {
          model: choices.field ? choices.field.options : []

          delegate: Rectangle {
            id: choice
            required property var modelData
            required property int index
            readonly property bool selected: choices.value === choice.modelData.value
            width: choiceLabel.implicitWidth + Style.spacing.lg * 2
            height: Style.space(28)
            radius: root.menuRowRadius
            color: choice.selected ? root.colAccent : (choiceMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : Util.alpha(root.colPopupText, 0.08))

            Text {
              textFormat: Text.PlainText
              id: choiceLabel
              anchors.centerIn: parent
              text: choice.modelData.label
              color: choice.selected ? root.colPopupBackground : root.colPopupText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: choiceMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: choices.commit(choice.modelData.value)
            }
          }
        }
      }
    }

    Component {
      id: stepperEditor
      Row {
        id: stepper
        property var field: null
        property var value: 0
        signal commit(var next)
        spacing: Style.spacing.sm

        function step(direction) {
          var f = stepper.field
          var next = Number(stepper.value) + direction * f.step
          stepper.commit(Math.max(f.min, Math.min(f.max, next)))
        }

        Rectangle {
          width: Style.space(28)
          height: width
          radius: root.menuRowRadius
          color: minusMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : Util.alpha(root.colPopupText, 0.08)
          Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "−"; color: root.colPopupText; font.pixelSize: Style.font.body }
          MouseArea { id: minusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stepper.step(-1) }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: undefined
          width: Style.space(66)
          height: Style.space(28)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: stepper.value + (stepper.field && stepper.field.unit ? " " + stepper.field.unit : "")
          color: root.colPopupText
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Rectangle {
          width: Style.space(28)
          height: width
          radius: root.menuRowRadius
          color: plusMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : Util.alpha(root.colPopupText, 0.08)
          Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "+"; color: root.colPopupText; font.pixelSize: Style.font.body }
          MouseArea { id: plusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stepper.step(1) }
        }
      }
    }

    Component {
      id: sliderEditor
      Row {
        id: slider
        property var field: null
        property var value: 0
        signal commit(var next)
        spacing: Style.spacing.md
        // The knob follows the pointer while dragging; the value is written
        // once, on release, so a drag is one config write, not hundreds.
        property real dragValue: -1
        readonly property real shown: slider.dragValue >= 0 ? slider.dragValue : Number(slider.value)

        Item {
          id: track
          width: Style.space(160)
          height: Style.space(24)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Util.alpha(root.colPopupText, 0.25)

            Rectangle {
              width: slider.field ? parent.width * (slider.shown - slider.field.min) / (slider.field.max - slider.field.min) : 0
              height: parent.height
              radius: 2
              color: root.colAccent
            }
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14)
            height: width
            radius: width / 2
            color: root.colAccent
            x: slider.field ? (track.width - width) * (slider.shown - slider.field.min) / (slider.field.max - slider.field.min) : 0
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function valueAt(x) {
              var f = slider.field
              var ratio = Math.max(0, Math.min(1, x / track.width))
              var raw = f.min + ratio * (f.max - f.min)
              return Math.round(raw / f.step) * f.step
            }
            onPressed: function (mouse) { slider.dragValue = valueAt(mouse.x) }
            onPositionChanged: function (mouse) { if (pressed) slider.dragValue = valueAt(mouse.x) }
            onReleased: {
              var next = slider.dragValue
              slider.dragValue = -1
              if (next >= 0) slider.commit(Math.round(next * 100) / 100)
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: Style.space(40)
          height: Style.space(24)
          verticalAlignment: Text.AlignVCenter
          text: Math.round(slider.shown * 100) + "%"
          color: root.colPopupText
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }

    Component {
      id: textEditor
      Rectangle {
        id: textBox
        property var field: null
        property var value: ""
        signal commit(var next)
        implicitWidth: Style.space(260)
        implicitHeight: Style.space(30)
        width: implicitWidth
        height: implicitHeight
        radius: root.menuRowRadius
        color: Util.alpha(root.colPopupText, 0.08)
        border.width: input.activeFocus ? 1 : 0
        border.color: root.colAccent

        PlainField {
          id: input
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.md
          color: root.colPopupText
          fontFamily: Style.font.family
          fontPixelSize: Style.font.body
          text: textBox.value === undefined || textBox.value === null ? "" : String(textBox.value)
          onEditingFinished: {
            if (input.text !== String(textBox.value)) textBox.commit(input.text)
          }
        }
      }
    }

    Component {
      id: listEditor
      Column {
        id: listBox
        property var field: null
        property var value: null
        signal commit(var next)
        spacing: Style.spacing.xs

        // Unset means the Start menu uses your XDG folders.
        readonly property bool isDefault: listBox.value === null || listBox.value === undefined
        readonly property var items: listBox.isDefault ? [] : listBox.value

        function seedFromDefaults() {
          var places = StartMenu.effectivePlaces(dockSettings.startPlaces, userDirsForSettings.text(), Quickshell.env("HOME") || "")
          var paths = []
          for (let i = 0; i < places.length; i++) paths.push(places[i].path)
          listBox.commit(paths)
        }

        function replaceAt(index, text) {
          var next = listBox.items.slice()
          next[index] = text
          listBox.commit(next)
        }

        function removeAt(index) {
          var next = listBox.items.slice()
          next.splice(index, 1)
          listBox.commit(next)
        }

        Text {
          textFormat: Text.PlainText
          visible: listBox.isDefault
          text: "Default: Home and your Documents, Downloads, Pictures, Music and Videos folders"
          color: Util.alpha(root.colPopupText, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: listBox.items

          delegate: Row {
            id: placeEntry
            required property string modelData
            required property int index
            spacing: Style.spacing.sm

            Rectangle {
              width: listBox.width - Style.space(34)
              height: Style.space(30)
              radius: root.menuRowRadius
              color: Util.alpha(root.colPopupText, 0.08)
              border.width: placeInput.activeFocus ? 1 : 0
              border.color: root.colAccent

              PlainField {
                id: placeInput
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
                color: root.colPopupText
                fontFamily: Style.font.family
                fontPixelSize: Style.font.body
                text: placeEntry.modelData
                onEditingFinished: if (placeInput.text !== placeEntry.modelData) listBox.replaceAt(placeEntry.index, placeInput.text)
              }
            }

            Rectangle {
              width: Style.space(28)
              height: width
              radius: root.menuRowRadius
              color: removeMouse.containsMouse ? Util.alpha(Color.urgent, 0.5) : "transparent"
              Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "✕"; color: root.colPopupText; font.pixelSize: Style.font.caption }
              MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: listBox.removeAt(placeEntry.index) }
            }
          }
        }

        Row {
          spacing: Style.spacing.sm

          Rectangle {
            width: addLabel.implicitWidth + Style.spacing.lg * 2
            height: Style.space(28)
            radius: root.menuRowRadius
            color: addMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : Util.alpha(root.colPopupText, 0.08)
            Text {
              textFormat: Text.PlainText
              id: addLabel
              anchors.centerIn: parent
              text: listBox.isDefault ? "Customize" : "Add folder"
              color: root.colPopupText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: addMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (listBox.isDefault) listBox.seedFromDefaults()
                else listBox.commit(listBox.items.concat(["~/"]))
              }
            }
          }

          Rectangle {
            visible: !listBox.isDefault
            width: useDefaultLabel.implicitWidth + Style.spacing.lg * 2
            height: Style.space(28)
            radius: root.menuRowRadius
            color: useDefaultMouse.containsMouse ? Style.hoverFillFor(root.colForeground, root.colAccent) : Util.alpha(root.colPopupText, 0.08)
            Text {
              textFormat: Text.PlainText
              id: useDefaultLabel
              anchors.centerIn: parent
              text: "Use defaults"
              color: root.colPopupText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: useDefaultMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: listBox.commit(undefined)
            }
          }
        }
      }
    }
  }

  // reserveSpace (SPEC.md "The bar"): an invisible window on the Dock's edge
  // whose exclusive zone keeps tiled and maximized windows clear of the bar.
  // On the Overlay layer so Hyprland arranges it after the Omarchy bar and
  // the panel below: on a lower layer it would claim the edge first, pushing
  // the Omarchy bar down and squeezing the panel by its own zone. It has no
  // input region, so being the topmost layer costs nothing.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: reserveWindow
      required property var modelData
      screen: modelData
      visible: root.taskbar.reserveSpace && !root.autoHide
      color: "transparent"
      mask: Region {}

      WlrLayershell.namespace: "omarchy-startbar-reserve"
      WlrLayershell.layer: WlrLayer.Overlay
      exclusiveZone: root.taskbar.barHeight

      anchors {
        left: !reserveWindow.edge.right
        right: !reserveWindow.edge.left
        top: !reserveWindow.edge.bottom
        bottom: !reserveWindow.edge.top
      }
      readonly property var edge: DockGeometry.edge(root.taskbar.position)
      implicitWidth: edge.vertical ? root.taskbar.barHeight : 0
      implicitHeight: edge.vertical ? 0 : root.taskbar.barHeight
    }
  }

  Variants {
    id: panels
    model: Quickshell.screens

    PanelWindow {
      id: panel

      required property var modelData
      screen: modelData
      visible: true
      color: "transparent"

      WlrLayershell.namespace: "omarchy-startbar"
      WlrLayershell.layer: WlrLayer.Top
      // Exclusive while the built-in Start menu is open, hover-shown or not,
      // so typing searches it wherever the pointer is. (A popup's grab would
      // have pulled pointer focus off the Start button; this does not.)
      WlrLayershell.keyboardFocus: startMenu.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      // exclusiveZone 0 with Normal mode reserves no space of our own but
      // still keeps us out of any space another layer surface (the bar)
      // has already claimed, so the panel's own geometry lands above it
      // automatically with no manual bar-height bookkeeping.
      exclusiveZone: 0
      exclusionMode: ExclusionMode.Normal

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      // With reserveSpace the window above keeps the bar's room clear of this
      // one as well, which would leave the Dock floating beside an empty
      // strip: a negative margin on the Dock's own edge takes the room back.
      readonly property real reserved: root.taskbar.reserveSpace && !root.autoHide ? root.taskbar.barHeight : 0
      margins {
        top: panel.edge.top ? -panel.reserved : 0
        bottom: panel.edge.bottom ? -panel.reserved : 0
        left: panel.edge.left ? -panel.reserved : 0
        right: panel.edge.right ? -panel.reserved : 0
      }

      // The input region is the union of the Reveal Strip and the Dock
      // itself: whichever one the Row's slide currently makes zero-area
      // simply contributes nothing, so this holds for both Dock states.
      mask: Region {
        Region { item: revealStrip }
        Region { item: bar }
        Region { item: dockRow }
        Region { item: startButton }
        Region { item: clock }
        Region { item: startMenu }
        Region { item: startDismiss }
      }

      // Whether the Dock/bar is on screen: always, unless it auto-hides, in
      // which case it follows the Revealed state.
      readonly property bool shown: !root.autoHide || revealState.revealed

      // The Dock's edge (SPEC.md "The Dock's position") and where everything
      // on it sits: DockGeometry.js decides, the rectangles below are bound to
      // it. `reveal` is 0 while the Dock is Hidden and 1 at rest; the slide is
      // this one animation, so every element moves together.
      readonly property var edge: DockGeometry.edge(root.taskbar.position)
      property real reveal: panel.shown ? 1 : 0
      Behavior on reveal {
        NumberAnimation { duration: root.slideDurationMs; easing.type: Easing.InOutCubic }
      }
      // `edgeSpacing` (12): the space before the Start button at the bar's start
      // and, the same, between a popup's card and the bar it rises from, as on
      // Windows 11 (SPEC.md "The Dock's position"); the Start menu's side margin
      // is the Start button's, so the two match.
      readonly property real edgePad: root.taskbar.edgeSpacing
      readonly property real popupGap: panel.edgePad
      readonly property var geo: DockGeometry.layout({
        position: root.taskbar.position,
        alignment: root.taskbar.alignment,
        barHeight: root.taskbar.barHeight,
        panelWidth: panel.width,
        panelHeight: panel.height,
        shown: panel.reveal,
        autoHide: root.autoHide,
        revealStripHeight: root.revealStripHeight,
        edgePad: panel.edgePad,
        start: { size: startButton.width },
        clock: { visible: clock.visible, width: clock.width, height: clock.height },
        row: { width: dockRow.width, height: dockRow.height },
      })

      // Where everything is on this monitor, in pixels from its top-left
      // corner, for `omarchy-shell <id> layout` (scripts/screenshots.sh and
      // scripts/pointer.sh read it instead of finding things in a screenshot):
      // { monitor, items: [{ key, kind, appId, count, x, y, width, height }],
      //   menus: { item, bar, preview, start } } with a menu's rectangle when it is open.
      // The panel covers the monitor less any bar reserved at an edge, so its
      // own offset is the monitor's size less its own.
      function layout() {
        var ox = panel.screen.width - panel.width
        var oy = panel.screen.height - panel.height
        function rect(x, y, w, h) {
          return { x: Math.round(x + ox), y: Math.round(y + oy), width: Math.round(w), height: Math.round(h) }
        }
        function ofItem(it) {
          var p = it.mapToItem(null, 0, 0)
          return rect(p.x, p.y, it.width, it.height)
        }
        // A popup window is as big as its menu plus the shadow's room all round.
        function ofPopup(w) {
          return w.visible ? rect(w.relativeX + root.menuShadow, w.relativeY + root.menuShadow,
            w.implicitWidth - root.menuShadow * 2, w.implicitHeight - root.menuShadow * 2) : null
        }
        var items = []
        for (let i = 0; i < repeater.count; i++) {
          let it = repeater.itemAt(i)
          if (!it || !it.modelData) continue
          let r = ofItem(it)
          r.key = it.key
          r.kind = it.modelData.kind
          r.appId = root.menuAppId(it.modelData) || ""
          r.count = it.modelData.count || 1
          items.push(r)
        }
        return {
          monitor: panel.screen.name,
          items: items,
          menus: {
            item: ofPopup(contextMenu),
            bar: ofPopup(barMenu),
            // Anchored to the Bar menu, so its place is relative to that window.
            // (On the right Dock it opens on the menu's left: relativeX is where its
            // anchor sits, and the window extends leftward from there.)
            barSub: barSubMenu.visible ? rect(barMenu.relativeX + barSubMenu.relativeX + root.menuShadow
              - (barSubMenu.opening.opensLeft ? barSubMenu.implicitWidth : 0),
              barMenu.relativeY + barSubMenu.relativeY + root.menuShadow,
              barSubMenu.implicitWidth - root.menuShadow * 2, barSubMenu.implicitHeight - root.menuShadow * 2) : null,
            preview: ofPopup(previewPopup),
            start: startMenu.visible ? rect(startMenu.x, startMenu.y, startMenu.width, startMenu.height) : null,
          },
        }
      }

      // Full-width, above any bar reservation because it's anchored to
      // this panel's own bottom edge, which ExclusionMode.Normal already
      // keeps clear of the bar's exclusive zone (see exclusionMode above).
      Item {
        id: revealStrip
        x: panel.geo.strip.x
        y: panel.geo.strip.y
        width: panel.geo.strip.width
        height: panel.geo.strip.height

        HoverHandler {
          onHoveredChanged: revealState.set("strip", hovered)
        }
      }

      // Hidden/Revealed and the reveal/hide timers (SPEC.md "How the Dock
      // behaves"). Kept per panel, so hovering one monitor's Reveal Strip
      // never reveals the other monitor's Dock. menuOpen holds the Dock
      // Revealed for the whole of a context-menu visit (SPEC.md "How the Dock
      // behaves": it stays Revealed while a menu is open) independent of
      // hover, since the pointer moves onto the menu's own popup window
      // and away from both the strip and the Dock itself. dragging does
      // the same for the whole of a drag (SPEC.md "How the Dock behaves":
      // Revealed for the whole of a drag, the hide timer starts after the
      // drop): once it drops back to false the hide timer starts
      // exactly like it does when hover ends, with no separate handling
      // needed here.
      QtObject {
        id: revealState

        // The rules live in DockInteraction.js; this holds its state and arms
        // the timers a transition asks for.
        property var model: DockInteraction.initialReveal()
        readonly property bool revealed: revealState.model.revealed

        // `name` is one of strip, dock, bar, start, preview, menu, barMenu,
        // startMenu, drag.
        function set(name, value) {
          revealState.apply(DockInteraction.setRevealFlag(revealState.model, name, value))
        }

        function apply(result) {
          revealState.model = result.state
          if (result.timers.hide === "stop") hideTimer.stop()
          else if (result.timers.hide === "start") hideTimer.restart()
          if (result.timers.reveal === "stop") revealTimer.stop()
          else if (result.timers.reveal === "start") revealTimer.restart()
        }
      }

      Timer {
        id: revealTimer
        interval: root.revealDelayMs
        onTriggered: revealState.apply(DockInteraction.revealTimerFired(revealState.model))
      }

      Timer {
        id: hideTimer
        interval: root.hideDelayMs
        onTriggered: revealState.apply(DockInteraction.hideTimerFired(revealState.model))
      }

      // The full-width bar. Slides away with the Hidden/Revealed rule when
      // it auto-hides.
      Rectangle {
        id: bar
        // Placed by x/y, not anchors, in this and the Items below: swapping
        // anchors with the edge leaves both set for a moment, and Qt then
        // sizes an Item from them (a Row's height went negative).
        x: panel.geo.bar.x
        y: panel.geo.bar.y
        width: panel.geo.bar.width
        height: panel.geo.bar.height
        color: root.taskbar.transparent ? "transparent" : Util.alpha(root.colBackground, root.glassy ? Math.min(root.taskbar.opacity, 0.35) : root.taskbar.opacity)

        HoverHandler {
          onHoveredChanged: revealState.set("bar", hovered)
        }

        // Right click on the bar itself (Item MouseAreas above it take their
        // own clicks first) opens the bar's options menu. A TapHandler, not
        // a MouseArea, so it can't take hover from the HoverHandler above.
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: function (eventPoint) {
            var at = bar.mapToItem(panel.contentItem, eventPoint.position.x, eventPoint.position.y)
            barMenu.openAt(at.x, at.y)
          }
        }

        Rectangle {
          visible: !root.taskbar.transparent
          // The bar's 1 px edge facing the screen.
          x: panel.geo.border.x
          y: panel.geo.border.y
          width: panel.geo.border.width
          height: panel.geo.border.height
          color: Util.alpha(root.colBorder, 0.6)
        }
      }

      // Start button: runs the configured command (by default the Omarchy
      // apps menu). Sits just left of the Items, so it is part of the
      // centred group.
      Rectangle {
        id: startButton
        visible: root.taskbar.showStart
        width: visible ? root.taskbar.barHeight - 8 : 0
        height: width
        radius: Style.cornerRadius
        x: panel.geo.start.x
        y: panel.geo.start.y
        color: startMouse.containsMouse ? Util.alpha(root.colForeground, 0.12) : "transparent"

        readonly property var iconSpec: DockConfig.resolveStartIcon(root.taskbar.startIcon)

        // The built-in grid: four panes, drawn here so no artwork ships.
        Grid {
          visible: startButton.iconSpec.kind === "grid"
          anchors.centerIn: parent
          columns: 2
          spacing: 3
          Repeater {
            model: 4
            Rectangle {
              width: Math.round(startButton.width * 0.27)
              height: width
              radius: 2
              color: root.colAccent
            }
          }
        }

        Image {
          visible: startButton.iconSpec.kind !== "grid"
          anchors.centerIn: parent
          width: Math.round(startButton.width * 0.6)
          height: width
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: startButton.iconSpec.kind === "path"
            ? "file://" + startButton.iconSpec.value
            : (startButton.iconSpec.kind === "icon" ? root.iconSource(startButton.iconSpec.value) : "")
        }

        // The MouseArea below takes hover away from the bar's own handler
        // (this button is the bar's sibling, not its child), so it keeps the
        // bar Revealed itself.
        HoverHandler {
          onHoveredChanged: revealState.set("start", hovered)
        }

        // The built-in menu's open/close rules (resting here opens it after a
        // moment, clicking toggles it, a hover-opened one closes when the
        // pointer leaves) live in StartMenu.js; this only reports what the
        // pointer and the keyboard command did.
        Connections {
          target: root
          function onStartMenuRequested(screenName, action) {
            if (panel.screen.name !== screenName) return
            startMenu.send({ type: "command", action: action })
          }
        }

        MouseArea {
          id: startMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: startMenu.send({ type: "buttonHover", hovered: startMouse.containsMouse })
          onClicked: startMenu.send({ type: "buttonClick" })
        }
      }

      // Clock at the bar's right end. The wrapper's size is what the mask and
      // layout see, zero while hidden.
      Item {
        id: clock
        visible: root.taskbar.showClock
        width: visible ? clockLabel.implicitWidth : 0
        height: clockLabel.implicitHeight
        // Placed by x/y, not anchors: swapping the anchors with the edge made
        // Qt report an anchor loop against this Item's own height.
        x: panel.geo.clock.x
        y: panel.geo.clock.y

        Text {
          textFormat: Text.PlainText
          id: clockLabel
          horizontalAlignment: panel.edge.vertical ? Text.AlignHCenter : Text.AlignRight
          color: root.colForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          // The column is only barHeight wide: a short date there.
          text: (panel.edge.vertical ? Qt.formatTime(clockTimer.now, "hh:mm") : Qt.formatTime(clockTimer.now, Locale.ShortFormat)) + "\n"
            + (panel.edge.vertical ? Qt.formatDate(clockTimer.now, "d MMM") : Qt.formatDate(clockTimer.now, Locale.ShortFormat))
        }

        Timer {
          id: clockTimer
          property date now: new Date()
          interval: 15000
          repeat: true
          running: clock.visible
          triggeredOnStart: true
          onTriggered: clockTimer.now = new Date()
        }
      }

      // A row of Items, or a column of them on a side Dock. A Grid so one
      // item does both (a single column, or a single row).
      Grid {
        id: dockRow

        readonly property bool vertical: panel.edge.vertical
        columns: dockRow.vertical ? 1 : Math.max(1, repeater.count)
        spacing: 2

        // Hidden parks the Items beyond the visible edge without unmapping the
        // panel itself; Revealed rests them in the bar (DockGeometry.js).
        x: panel.geo.row.x
        y: panel.geo.row.y

        HoverHandler {
          onHoveredChanged: revealState.set("dock", hovered)
        }

        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: function (eventPoint) {
            var at = dockRow.mapToItem(panel.contentItem, eventPoint.position.x, eventPoint.position.y)
            barMenu.openAt(at.x, at.y)
          }
        }

        // Icons are at most iconSize and fit inside the bar and, with many
        // Items, its length (DockGeometry.iconSize); each Item has side padding
        // for a roomier hit area. `slot` is where the icon and the dots stand in
        // an Item; itemLength is what one Item occupies along the bar, and
        // everything that steps through it uses it.
        readonly property int pad: 16
        readonly property int iconSize: DockGeometry.iconSize({
          position: root.taskbar.position,
          panelWidth: panel.width,
          panelHeight: panel.height,
          barHeight: root.taskbar.barHeight,
          iconSize: root.iconSize,
          pad: dockRow.pad,
          spacing: dockRow.spacing,
          edgePad: panel.edgePad,
          count: repeater.count,
          start: { size: startButton.width },
          clock: { visible: clock.visible, width: clock.width, height: clock.height },
        })
        readonly property int itemWidth: iconSize + pad
        readonly property var slot: DockGeometry.slot(root.taskbar.position, dockRow.iconSize, Style.spacing.xxs)
        readonly property int itemLength: dockRow.vertical ? dockRow.slot.height : dockRow.itemWidth
        // The distance between two Items' slots along the bar.
        readonly property real step: itemLength + spacing

        // Drag to reorder (docs/SPEC.md "Input"; CONTEXT.md "Placed"). The
        // dragged Item's own delegate stays put in the Repeater (so every
        // other Item's slot is undisturbed — reordering this Row's own
        // model mid-drag would make the Repeater tear down and rebuild
        // every delegate, destroying the very Item whose MouseArea is
        // driving the drag) but renders invisible for as long as its key
        // matches dragKey. dragProbe (declared below, a sibling of this
        // Row) is what the pointer drags; dragGhost shows the Item in its
        // place, a little bigger than the rest and stopping at the first
        // and last slot; the Items between the two slots step aside by
        // dragShift, so the gap shows where a drop would land. dragKey
        // empty means "no drag in progress".
        property var drag: DockInteraction.initialDrag()
        readonly property string dragKey: dockRow.drag.key
        // True from the drop until the Items have been reordered, so their
        // dragShift snaps back to 0 instead of gliding against the reorder.
        property bool dropping: false

        function indexOfKey(items, key) {
          for (let i = 0; i < items.length; i++) {
            if (items[i].key === key) return i
          }
          return -1
        }

        // Recomputed from dragGhost's own position (docs/SPEC.md "Input")
        // as it follows the pointer, in this Row's own parent's coordinate
        // space — the same space dragGhost.x/y are set in, since both are
        // children of it (see dragGhost below).
        function updateDragPreview() {
          if (!dockRow.dragKey) return
          var f = DockInteraction.onAxis(dockRow.vertical, dockRow.ghostCenter(), dockRow.rect())
          dockRow.drag = DockInteraction.dragMove(dockRow.drag, f.ghost, f.row,
            dockRow.step, dockRow.iconSize, dockState.items.length)
          var along = DockInteraction.clampGhostX(dockRow.vertical ? dragProbe.y : dragProbe.x, f.row,
            dockRow.step, dockState.items.length)
          dragGhost.x = dockRow.vertical ? dragProbe.x : along
          dragGhost.y = dockRow.vertical ? along : dragProbe.y
        }

        // Where the pointer has taken the Item, not where the ghost is
        // drawn: the ghost stops at the ends of the row, the pointer does not.
        function ghostCenter() {
          return { x: dragProbe.x + dragProbe.width / 2, y: dragProbe.y + dragProbe.height / 2 }
        }

        function rect() {
          return { x: dockRow.x, y: dockRow.y, width: dockRow.width, height: dockRow.height }
        }

        // The drop (docs/SPEC.md "Input"; the decision is
        // DockInteraction.dragDrop): reorder within the Dock, unpin for an
        // Item whose App is pinned dragged out, or (an unpinned Window Item
        // dragged out) a snap-back with nothing to persist — dragGhost
        // simply stops following the pointer and every Item, this one
        // included, falls back to dockState.items' own order. Drag state
        // (root.dragInProgress included) clears first, so the refresh
        // placeItem/unpinFromDrag triggers isn't the one dockState.refresh's
        // own drag guard skips.
        function finishDrag(item) {
          var f = DockInteraction.onAxis(dockRow.vertical, dockRow.ghostCenter(), dockRow.rect())
          var decision = DockInteraction.dragDrop(dockRow.drag, f.ghost, f.row,
            dockRow.iconSize, { pinned: item.kind === "pin" || !!item.pinned })

          var from = dockRow.drag.from
          dockRow.dropping = true
          dockRow.drag = DockInteraction.initialDrag()
          revealState.set("drag", false)
          root.dragInProgress = false

          // The ghost settles into the slot the Item now has, then gives way
          // to it; a drag-out has no slot to settle into.
          if (decision.action === "unpin") {
            dragGhost.visible = false
            root.unpinFromDrag(root.menuAppId(item))
          } else {
            let slot = decision.action === "reorder" ? decision.index : from
            dockRow.settlingKey = item.key
            settleX.to = dockRow.vertical ? dockRow.dragHomeX : dockRow.x + slot * dockRow.step
            settleY.to = dockRow.vertical ? dockRow.y + slot * dockRow.step : dockRow.dragHomeY
            dragGhost.scale = 1
            settle.restart()
            if (decision.action === "reorder") root.placeItem(item, decision.index)
          }
          Qt.callLater(function () { dockRow.dropping = false })
        }

        // The Item whose ghost is still settling into its slot, and where the
        // ghost's top edge rests (where the Item's own was when pressed).
        property string settlingKey: ""
        property real dragHomeX: 0
        property real dragHomeY: 0

        Repeater {
          id: repeater
          model: dockItemKeys

          delegate: Item {
            id: dockItem
            required property string key
            required property int index
            // The Item itself, looked up by key; it keeps the last one found
            // for the moment between an Item going and its delegate going.
            readonly property var live: dockState.itemByKey[dockItem.key]
            property var modelData: ({})
            onLiveChanged: if (dockItem.live) dockItem.modelData = dockItem.live
            Component.onCompleted: if (dockItem.live) dockItem.modelData = dockItem.live

            readonly property bool active: dockItem.modelData.active
            readonly property bool attention: dockItem.modelData.attention
            readonly property bool isPin: dockItem.modelData.kind === "pin"
            // Guards onClicked below: MouseArea still emits clicked() on
            // release after a drag.target drag, so without this a drop
            // would also focus/launch the Item it was just dropped near.
            property bool wasDragged: false

            opacity: dockRow.dragKey === dockItem.key || dockRow.settlingKey === dockItem.key ? 0 : 1

            // Items the dragged one has passed step aside by one slot, and a
            // pressed Item shrinks a little before it is lifted.
            property real dragShift: dockRow.dragKey !== ""
              ? DockInteraction.slotShift(dockRow.drag, dockItem.index, dockRow.step) : 0
            Behavior on dragShift {
              enabled: !dockRow.dropping
              NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            transform: Translate {
              x: dockRow.vertical ? 0 : dockItem.dragShift
              y: dockRow.vertical ? dockItem.dragShift : 0
            }
            scale: (mouseArea.pressedButtons & Qt.LeftButton) && dockRow.dragKey === "" ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            width: dockRow.itemWidth
            height: dockRow.slot.height

            // The Active Window's highlight and the Attention tint (SPEC.md
            // "Indicators"): CONTEXT.md says the Window Item itself is
            // highlighted/tinted, so these cover the whole Item — icon and
            // running dot both — not just the icon square. Drawn behind the
            // icon so both can show at once without fighting the icon/Letter
            // Tile for the same Rectangle.
            Rectangle {
              visible: dockItem.active
              anchors.fill: parent
              radius: Style.cornerRadius
              color: Style.selectedFill
              border.width: Style.selectedBorderWidth
              border.color: Style.selectedBorderColor
            }

            Rectangle {
              visible: dockItem.attention
              anchors.fill: parent
              radius: Style.cornerRadius
              color: Util.alpha(Color.urgent, 0.35)
            }

            // A Group Item (groupWindows, docs/SPEC.md "Grouping") shows the
            // edges of the Windows stacked behind its icon, as Windows does.
            Repeater {
              model: Math.min(dockItem.modelData.count || 1, 3) - 1

              Item {
                id: copy
                required property int index
                readonly property real shrink: 1 - (index + 1) * 0.12
                z: -1 - index
                width: icon.width * shrink
                height: icon.height * shrink
                x: icon.x + icon.width - width + (index + 1) * Style.space(4)
                y: icon.y + (icon.height - height) / 2
                opacity: 0.85 - index * 0.25

                Image {
                  visible: source.toString() !== ""
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  sourceSize.width: width * Screen.devicePixelRatio
                  sourceSize.height: height * Screen.devicePixelRatio
                  source: dockItem.modelData.app ? root.iconSource(dockItem.modelData.app.icon) : ""
                }

                // A Letter Tile Window has no icon to copy.
                Rectangle {
                  visible: dockItem.modelData.app === null
                    || root.iconSource(dockItem.modelData.app.icon) === ""
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: root.colMuted
                }
              }
            }

            Item {
              id: icon
              anchors.top: parent.top
              // The icon's place in its Item leaves room for the dots beside it.
              anchors.topMargin: dockRow.slot.iconTopMargin
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: dockRow.slot.iconOffset
              width: dockRow.iconSize
              height: dockRow.iconSize

              Image {
                visible: source.toString() !== ""
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: dockItem.modelData.app ? root.iconSource(dockItem.modelData.app.icon) : ""
              }

              // The Letter Tile: no App, or an App whose icon file is not
              // found (yet).
              Rectangle {
                visible: dockItem.modelData.app === null
                  || (root.iconSource(dockItem.modelData.app.icon) === "" && !root.icons.pending(dockItem.modelData.app.icon))
                anchors.fill: parent
                radius: Style.cornerRadius
                color: root.colMuted

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: dockItem.modelData.letter || root.appLetter(dockItem.modelData.app)
                  color: root.colForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                }
              }

              // Workspace badge (docs/SPEC.md "Indicators"): the model
              // has already turned a special workspace's "special:" IPC
              // name into its own name.
              Rectangle {
                visible: root.taskbar.showWorkspaceBadge && (dockItem.modelData.badge || "").length > 0
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                radius: height / 2
                color: root.colBackground
                border.width: Style.normalBorderWidth
                border.color: root.colMuted
                width: Math.max(height, badgeText.implicitWidth + Style.spacing.xs * 2)
                height: Style.font.caption + Style.spacing.xxs * 2

                Text {
                  textFormat: Text.PlainText
                  id: badgeText
                  anchors.centerIn: parent
                  text: dockItem.modelData.badge || ""
                  color: root.colForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                // Only a left-button press drags (docs/SPEC.md "Input"
                // reserves right/middle for the menu and launching); drag
                // moves dragGhost, a sibling of dockRow, not this Item
                // itself — dockRow is a positioner and would fight any
                // attempt to move dockItem directly.
                drag.target: dragProbe

                onContainsMouseChanged: {
                  if (mouseArea.containsMouse) previewState.hoverStart(dockItem)
                  else previewState.hoverEnd()
                }

                onPressed: function (mouse) {
                  dockItem.wasDragged = false
                  if (mouse.button !== Qt.LeftButton) {
                    mouseArea.drag.target = null
                    return
                  }
                  mouseArea.drag.target = dragProbe
                  dragGhost.item = dockItem.modelData
                  var origin = dockItem.mapToItem(dockRow.parent, 0, 0)
                  dragProbe.x = origin.x
                  dragProbe.y = origin.y
                  dockRow.dragHomeX = origin.x
                  dockRow.dragHomeY = origin.y
                  settle.stop()
                  dockRow.settlingKey = ""
                  dragProbe.width = dockItem.width
                  dragProbe.height = dockItem.height
                  dragGhost.x = origin.x
                  dragGhost.y = origin.y
                  dragGhost.width = dockItem.width
                  dragGhost.height = dockItem.height
                  dragGhost.scale = 0.88
                }

                drag.onActiveChanged: {
                  if (mouseArea.drag.active) {
                    dockItem.wasDragged = true
                    root.dragInProgress = true
                    revealState.set("drag", true)
                    dockRow.drag = DockInteraction.dragStart(dockItem.modelData.key, dockRow.indexOfKey(dockState.items, dockItem.modelData.key))
                    dragGhost.visible = true
                    dragGhost.scale = 1.15
                  } else if (dockRow.dragKey === dockItem.modelData.key) {
                    dockRow.finishDrag(dockItem.modelData)
                  }
                }

                onClicked: function (mouse) {
                  if (dockItem.wasDragged) return
                  if (mouse.button === Qt.RightButton) {
                    // Drop any hover preview first, so the menu never shows over it.
                    previewState.dismiss()
                    contextMenu.previewCell = null
                    contextMenu.previewWindowId = ""
                    contextMenu.anchorItem = dockItem
                    contextMenu.menuItem = dockItem.modelData
                    contextMenu.visible = true
                    return
                  }
                  // Middle click on any Item with a resolvable App launches
                  // a new instance (docs/SPEC.md "Input"); launchApp is
                  // already a no-op when there's no App to launch.
                  if (mouse.button === Qt.MiddleButton) {
                    root.launchApp(dockItem.modelData.app)
                    return
                  }
                  if (dockItem.isPin) {
                    root.launchApp(dockItem.modelData.app)
                    return
                  }
                  // A Group Item with a preview to pick from does nothing on
                  // click, as on Windows (docs/SPEC.md "Grouping"); without
                  // previews the click steps through the group's Windows.
                  if (dockItem.modelData.count > 1) {
                    if (!root.taskbar.showPreviews) root.focusNextInGroup(dockItem.modelData)
                    return
                  }
                  if (dockItem.active && dockItem.modelData.window.workspace !== "special:minimized") {
                    previewState.dismiss()
                    const command = DockHyprland.minimizeWindow(dockItem.modelData.window.id)
                    if (command) Quickshell.execDetached(command)
                    return
                  }
                  root.focusWindow(dockItem.modelData.window.id)
                }
              }

              // Bound to revealState.revealed, not just hover, so the
              // tooltip disappears the moment the Dock hides instead of
              // lingering until the pointer physically leaves the Item; it
              // has no hover handling of its own, so it never feeds
              // revealState and can't keep the Dock revealed on its own.
              PanelToolTip {
                visible: mouseArea.containsMouse && panel.shown && !previewState.enabledFor(dockItem.modelData)
                  && !root.pinHasNoTooltip(dockItem.modelData)
                text: dockItem.isPin
                  ? root.pinTooltipText(dockItem.modelData)
                  : root.windowTooltipText(dockItem.modelData)
              }
            }

            // The running dot (SPEC.md "Indicators"): every Window Item
            // shows one; a Pin with no Windows (CONTEXT.md "Pin") is the
            // only Item without it.
            // A Group Item shows up to three dots, one per Window; the
            // Active Window's is the wide accent pill.
            // Where they stand depends on the Dock's edge: under the icons on
            // the bottom Dock, above them on the top one, and in a column
            // beside them on the left and right.
            Grid {
              id: runningDot
              visible: !dockItem.isPin
              columns: dockRow.vertical ? 1 : 3
              readonly property var place: DockGeometry.dots(root.taskbar.position, dockItem.width,
                { y: icon.y, height: icon.height }, { width: runningDot.width, height: runningDot.height }, Style.spacing.xxs)
              x: runningDot.place.x
              y: runningDot.place.y
              spacing: 3

              Repeater {
                model: Math.min(dockItem.modelData.count || 1, 3)

                Rectangle {
                  required property int index
                  readonly property bool lead: index === 0
                  readonly property real length: lead && dockItem.active ? 16 : 6
                  width: dockRow.vertical ? 3 : length
                  height: dockRow.vertical ? length : 3
                  radius: 1.5
                  color: lead && dockItem.active ? root.colAccent : root.colForeground

                  Behavior on width {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }
                  Behavior on height {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }
                }
              }
            }
          }
        }
      }

      // What the pointer drags (mouseArea.drag.target above): an invisible
      // Item that goes wherever the pointer does, in this shared parent's
      // coordinate space, starting from wherever the dragged delegate's
      // onPressed measured it to be. dragGhost is drawn from it.
      Item {
        id: dragProbe
        visible: false
        onXChanged: dockRow.updateDragPreview()
        onYChanged: dockRow.updateDragPreview()
      }

      // The drop: the ghost glides into its slot, then the Item shows again.
      ParallelAnimation {
        id: settle
        onFinished: {
          dragGhost.visible = false
          dockRow.settlingKey = ""
        }
        NumberAnimation { id: settleX; target: dragGhost; property: "x"; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { id: settleY; target: dragGhost; property: "y"; duration: 120; easing.type: Easing.OutCubic }
      }

      // The floating icon of a drag (docs/SPEC.md "Input"): a little bigger
      // than the Items beside it, following the pointer sideways until it
      // reaches the first or last slot, where it stays while the pointer
      // goes on. A sibling of dockRow, not one of its Repeater delegates, so
      // dockRow's own positioning never fights its position.
      Item {
        id: dragGhost

        property var item: null

        visible: false
        z: 1000
        opacity: 0.95
        scale: 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Image {
          visible: source.toString() !== ""
          anchors.fill: parent
          anchors.leftMargin: dockRow.pad / 2
          anchors.rightMargin: dockRow.pad / 2
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: dragGhost.item && dragGhost.item.app ? root.iconSource(dragGhost.item.app.icon) : ""
        }

        Rectangle {
          visible: dragGhost.item && (dragGhost.item.app === null || root.iconSource(dragGhost.item.app.icon) === "")
          anchors.fill: parent
          radius: Style.cornerRadius
          color: root.colMuted

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: (dragGhost.item && (dragGhost.item.letter || root.appLetter(dragGhost.item.app))) || ""
            color: root.colForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }
        }
      }

      // Hover previews (showPreviews): a live thumbnail of the
      // hovered Window with its title and a close button. The rules are in
      // DockPreview.js (the Preview, Peek, the Preview menu holding it up);
      // previewState keeps its state, arms the timers it names and carries out
      // the effects. Hovering the popup itself keeps it (and the bar, via
      // revealState "preview") up.
      QtObject {
        id: previewState

        // Where the hovered Item is, in panel coordinates, captured at hover
        // time so the popup never depends on the delegate staying alive.
        property var anchorRect: ({ x: 0, y: 0, width: 0, height: 0 })
        property var model: DockPreview.initial()
        readonly property var hoveredItem: previewState.model.hovered
        readonly property var shownItem: previewState.model.shown
        readonly property bool showing: shownItem !== null

        function enabledFor(item) {
          return root.taskbar.showPreviews && item.kind === "window"
        }

        function send(event) {
          var result = DockPreview.transition(previewState.model, event,
            { previewPeek: root.taskbar.previewPeek, warp: root.taskbar.previewWarpPointer })
          // The state first: it can flip the popup's visibility, whose
          // handler sends its own event and reads the state as it now is.
          previewState.model = result.state
          previewState.arm(result.timers)
          for (let i = 0; i < result.effects.length; i++) previewState.perform(result.effects[i])
        }

        function arm(timers) {
          if (timers.open === "stop") previewOpenTimer.stop()
          else if (timers.open === "start") previewOpenTimer.restart()
          if (timers.leave === "stop") previewLeaveTimer.stop()
          else if (timers.leave === "start") previewLeaveTimer.restart()
          if (timers.peek === "stop") peekTimer.stop()
          else if (timers.peek === "start") peekTimer.restart()
          if (timers.peekRestore === "stop") peekRestoreTimer.stop()
          else if (timers.peekRestore === "start") peekRestoreTimer.restart()
        }

        function perform(effect) {
          switch (effect.type) {
          case "peek": root.peekWindow(effect.id); break
          case "restore": root.peekRestore(); break
          case "commit": root.peekCommit(); break
          case "focus":
            if (effect.warp) root.focusWindowAndWarp(effect.id)
            else root.focusWindow(effect.id)
            break
          }
        }

        function hoverStart(delegate) {
          // Moving on to an icon takes over from a hover-opened Start menu at
          // once, instead of both showing until the menu's leave timer fires.
          startMenu.send({ type: "itemHovered" })
          var enabled = enabledFor(delegate.modelData)
          // The anchor only moves for an Item that can have a Preview: a Pin
          // hovered while another Item's is up must not drag that one along.
          if (enabled && !root.dragInProgress) {
            let origin = delegate.mapToItem(panel.contentItem, 0, 0)
            previewState.anchorRect = { x: origin.x, y: origin.y, width: delegate.width, height: delegate.height }
          }
          previewState.send({ type: "hoverStart", item: delegate.modelData, enabled: enabled, dragging: root.dragInProgress })
        }

        function hoverEnd() {
          previewState.send({ type: "hoverEnd" })
        }

        function popupHover(hovered) {
          previewState.send({ type: "previewHover", hovered: hovered })
        }

        function dismiss() {
          previewState.send({ type: "dismiss" })
        }
      }

      Timer {
        id: previewOpenTimer
        interval: 350
        onTriggered: previewState.send({ type: "openFired" })
      }

      Timer {
        id: previewLeaveTimer
        interval: 250
        onTriggered: previewState.send({ type: "leaveFired" })
      }

      // Peek, debounced so sweeping the pointer along the thumbnails
      // doesn't flash every window in turn, and so passing between two
      // cells doesn't restore in between.
      Timer {
        id: peekTimer
        interval: 150
        onTriggered: previewState.send({ type: "peekFired" })
      }

      Timer {
        id: peekRestoreTimer
        interval: 200
        onTriggered: previewState.send({ type: "peekRestoreFired" })
      }

      // Keep the popup anchored if the hovered Item's position changes while
      // it is up (e.g. the row reflows).
      Connections {
        target: previewState
        function onAnchorRectChanged() {
          if (previewPopup.visible) previewPopup.anchor.updateAnchor()
        }
      }

      // One thumbnail per Window of the shown Item: a lone Window Item shows
      // its one, a Group Item (groupWindows) a row of them to pick from.
      // `liveItem` is the shown Item as the Dock has it now, matched by
      // Window id since a Group Item's key changes as Windows come and go,
      // so a Window closed from the popup drops out of it at once and the
      // popup closes with the last one.
      PopupWindow {
        id: previewPopup

        readonly property var liveItem: DockPreview.liveItem(previewState.shownItem, dockState.items)
        readonly property var liveWindows: liveItem ? (liveItem.windows || [liveItem.window]) : []
        // The thumbnail cells are keyed by Window id and only rebuilt when
        // the set of Windows changes. A peek moves focus, which rebuilds
        // the Items and so liveWindows; if the cells were rebuilt with it,
        // the one under the pointer would be destroyed, its hover would
        // end and the peek would be undone at once.
        property var windowIds: []
        onLiveWindowsChanged: windowIds = DockPreview.windowIds(windowIds, liveWindows)

        function windowFor(id) {
          for (let i = 0; i < liveWindows.length; i++) if (liveWindows[i].id === id) return liveWindows[i]
          return { id: id }
        }
        readonly property int thumbWidth: {
          var n = Math.max(1, windowIds.length)
          var room = panel.width - (panel.edge.vertical ? root.taskbar.barHeight : 0) - Style.spacing.xs * 2 - Style.spacing.sm * 2 - root.menuShadow * 2 - (Style.spacing.xs * 2 + Style.spacing.xs) * n
          return Math.max(Style.space(80), Math.min(Style.space(220), Math.floor(room / n)))
        }
        readonly property int thumbHeight: Math.round(thumbWidth * 124 / 220)

        readonly property color textColor: root.colPopupText
        readonly property color accentColor: root.colAccent

        // The delegates below can't see `root`, so they act through these.
        function focusPicked(window) {
          previewState.send({ type: "thumbPicked", window: window })
        }

        function peekHover(window, hovered) {
          previewState.send({ type: "thumbHover", window: window, hovered: hovered })
        }

        // Right click on a thumbnail: that Window's menu, above the thumbnail.
        // What happens to a peek meanwhile is DockPreview.js's "thumbMenu".
        function openMenu(cell, pointX, pointY) {
          previewState.send({ type: "thumbMenu", windowId: cell.modelData })
          contextMenu.close()
          contextMenu.previewCell = cell
          contextMenu.previewPointX = pointX
          contextMenu.previewPointY = pointY
          contextMenu.previewWindowId = cell.modelData
          contextMenu.anchorItem = null
          contextMenu.menuItem = null
          contextMenu.visible = true
        }

        function closePicked(window) {
          root.closeWindow(window.id)
        }

        visible: previewState.showing && liveItem !== null
        color: "transparent"
        // Room for the card's shadow on every side (see root.menuShadow).
        implicitWidth: previewRow.implicitWidth + Style.spacing.sm * 2 + root.menuShadow * 2
        implicitHeight: previewRow.implicitHeight + Style.spacing.sm * 2 + root.menuShadow * 2
        // Only the card takes the pointer, so the empty band that holds the
        // shadow never gets between the pointer and the Dock's icons.
        mask: Region { item: previewCard }

        onVisibleChanged: {
          revealState.set("preview", previewPopup.visible)
          // A Window outside every monitor would show a blank thumbnail.
          if (visible) root.rescueWindows(previewPopup.windowIds)
          previewSlideAnim.stop()
          if (visible && root.taskbar.previewSlide) previewSlideAnim.start()
          else slide = 1
          if (!previewPopup.visible) previewState.send({ type: "previewClosed" })
        }
        onImplicitWidthChanged: if (visible) previewPopup.anchor.updateAnchor()

        anchor {
          id: previewAnchor
          window: panel
          adjustment: PopupAdjustment.Slide
          edges: Edges.Top | Edges.Left
          gravity: Edges.Bottom | Edges.Right
          rect.width: 1
          rect.height: 1

          onAnchoring: {
            // Beside the Item, clear of the bar's edge, on the side facing into
            // the screen (DockPlacement.alongBar, .beside).
            var at = DockPlacement.beside(panel.edge, DockPlacement.alongBar(panel.edge, previewState.anchorRect, panel.geo.bar),
              { width: previewPopup.implicitWidth, height: previewPopup.implicitHeight },
              { width: panel.width, height: panel.height }, Style.spacing.xs, root.menuShadow, panel.popupGap)
            previewAnchor.rect.x = Math.round(at.x)
            previewAnchor.rect.y = Math.round(at.y)
          }
        }

        // 0 → 1 as the popup slides up into place; snaps to 1 when off.
        property real slide: 1
        readonly property var slideStep: DockPlacement.slide(panel.edge)
        NumberAnimation {
          id: previewSlideAnim
          target: previewPopup
          property: "slide"
          from: 0
          to: 1
          duration: 220
          easing.type: Easing.OutCubic
        }

        // Clips the card to the popup's own box, so it rises out from the
        // Dock's edge instead of fading in mid-air.
        Item {
          anchors.fill: parent
          clip: true

          RectangularShadow {
            anchors.fill: previewCard
            radius: previewCard.radius
            blur: root.menuShadow
            offset.y: Style.space(4)
            spread: 0
            color: Qt.rgba(0, 0, 0, 0.6)
          }

          Rectangle {
            id: previewCard
            // Slides out of the Dock's edge (DockPlacement.slide).
            x: root.menuShadow + previewPopup.slideStep.x * (1 - previewPopup.slide) * (width + root.menuShadow)
            width: parent.width - root.menuShadow * 2
            height: parent.height - root.menuShadow * 2
            radius: root.menuRadius
            color: root.colPopupBackground
            border.width: Style.normalBorderWidth
            border.color: root.colHairline
            y: root.menuShadow + previewPopup.slideStep.y * (1 - previewPopup.slide) * (height + root.menuShadow)

            HoverHandler {
              onHoveredChanged: previewState.popupHover(hovered)
            }

            Row {
              id: previewRow
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              spacing: Style.spacing.xs

              Repeater {
                model: previewPopup.windowIds

                // One Window's cell: a tinted background under the pointer, so
                // it is clear which thumbnail a click will pick.
                Item {
                  id: cell
                  required property var modelData
                  readonly property var win: previewPopup.windowFor(cell.modelData)
                  readonly property var toplevel: dockState.toplevelByAddress[cell.modelData] || null
                  readonly property int pad: Style.spacing.xs
                  implicitWidth: cellColumn.implicitWidth + pad * 2
                  implicitHeight: cellColumn.implicitHeight + pad * 2

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: cellHover.hovered ? Style.selectedFill : "transparent"
                  }

                  HoverHandler {
                    id: cellHover
                    onHoveredChanged: previewPopup.peekHover(cell.win, hovered)
                  }

                  // Anywhere on the cell: a left click picks this Window (the
                  // title and the padding too, not only the thumbnail), a right
                  // click opens its menu. The close button and the thumbnail
                  // sit above and take their own clicks first.
                  MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function (mouse) {
                      if (mouse.button === Qt.LeftButton) {
                        previewPopup.focusPicked(cell.win)
                        return
                      }
                      var at = mapToItem(previewPopup.contentItem, mouse.x, mouse.y)
                      previewPopup.openMenu(cell, previewAnchor.rect.x + at.x, previewAnchor.rect.y + at.y)
                    }
                  }

                Column {
                  id: cellColumn
                  x: cell.pad
                  y: cell.pad
                  spacing: Style.spacing.xs

                  Row {
                    width: previewPopup.thumbWidth
                    spacing: Style.spacing.xs

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width - closeButton.width - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter
                      elide: Text.ElideRight
                      color: previewPopup.textColor
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      text: dockState.titles[cell.modelData] || cell.win.title || cell.win.class || ""
                    }

                    Rectangle {
                      id: closeButton
                      width: Style.space(20)
                      height: width
                      radius: Style.cornerRadius
                      color: closeMouse.containsMouse ? Util.alpha(Color.urgent, 0.5) : "transparent"

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "\u2715"
                        color: previewPopup.textColor
                        font.pixelSize: Style.font.caption
                      }

                      MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          // The last Window closing takes the popup with it
                          // (liveItem goes null); otherwise it stays up so
                          // the rest can still be picked.
                          previewPopup.closePicked(cell.win)
                        }
                      }
                    }
                  }

                  // The thumbnail: a fixed-size box (so a Window that resizes or
                  // changes shape never resizes the popup), holding a live capture
                  // scaled to the Window's own aspect ratio. Live capture can
                  // blank for a frame when the Window's content changes a lot (a
                  // busy browser); the ShaderEffectSource underneath keeps the
                  // last frame the capture actually had, so that frame shows
                  // through instead of a flicker. Left-clicking the thumbnail
                  // focuses the Window, like its Item. In a group, the Active
                  // Window's thumbnail is outlined.
                  Item {
                    width: previewPopup.thumbWidth
                    height: previewPopup.thumbHeight

                    ShaderEffectSource {
                      anchors.centerIn: parent
                      width: capture.width
                      height: capture.height
                      sourceItem: capture
                      live: capture.hasContent
                      hideSource: false
                    }

                    ScreencopyView {
                      id: capture
                      anchors.centerIn: parent
                      constraintSize: Qt.size(previewPopup.thumbWidth, previewPopup.thumbHeight)
                      captureSource: previewPopup.visible ? cell.toplevel && cell.toplevel.wayland : null
                      live: true
                    }

                    Rectangle {
                      visible: previewPopup.windowIds.length > 1 && !!cell.win.active
                      anchors.fill: parent
                      color: "transparent"
                      radius: Style.cornerRadius
                      border.width: Style.selectedBorderWidth
                      border.color: previewPopup.accentColor
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        previewPopup.focusPicked(cell.win)
                      }
                    }
                  }
                }
                }
              }
            }
          }
        }
      }

      // Catches a click anywhere outside an open (non-hover) Start menu to
      // close it. Zero-sized otherwise, so it never gets in the way.
      Item {
        id: startDismiss
        z: 40
        width: (startMenu.open && !startMenu.hoverMode) ? panel.width : 0
        height: (startMenu.open && !startMenu.hoverMode) ? panel.height : 0

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onPressed: startMenu.send({ type: "dismiss" })
        }
      }

      // The built-in Start menu (startCommand "builtin"): StartMenuView.qml,
      // driven by StartMenu.js. Part of the panel, not a popup, so it can
      // hold the keyboard (see keyboardFocus on the panel); `send()` is the
      // only way in.
      StartMenuView {
        id: startMenu
        z: 50

        taskbar: root.taskbar
        edge: panel.edge
        dockGap: panel.popupGap
        settings: dockSettings
        scheme: root.scheme
        glassy: root.glassy
        panelWidth: panel.width
        panelHeight: panel.height
        buttonX: startButton.x
        buttonY: startButton.y
        buttonHovered: startMouse.containsMouse
        icons: root.icons

        onLaunchRequested: function (entry) { root.launchApp(entry) }
        onTogglePinRequested: function (appId, pinned) { root.togglePin(appId, pinned) }
        onDockHoldRequested: function (held) { revealState.set("startMenu", held) }
      }


      // The bar's quick menu: right click on the bar itself. Rows come from
      // DockConfig.barMenuRows; choosing one writes its patch through the
      // same write-back Pin/Unpin uses, so the bar updates live. A section
      // row (Colors, Start button...) opens its choices in a second popup
      // beside it, barSubMenu, as a traditional submenu does. Closes on any
      // choice or an outside click, and holds the bar Revealed while open,
      // like the Item context menu.
      PopupWindow {
        id: barMenu

        property real pointX: 0
        property real pointY: 0
        readonly property int menuMargin: Style.spacing.xs
        // The section whose submenu is open ("" for none), and where its
        // row is in this window; both reset when the menu closes.
        property string openSection: ""
        property real openRowY: 0
        readonly property var rows: DockConfig.barMenuRows(root.taskbar)
        readonly property var openRows: {
          for (let i = 0; i < barMenu.rows.length; i++) {
            if (barMenu.rows[i].children && barMenu.rows[i].label === barMenu.openSection) return barMenu.rows[i].children
          }
          return []
        }
        // Sized to its longest label (plus the check column, the value and
        // chevron of a section, and padding), so nothing is cut off however
        // long a row's label is; never narrower than a comfortable minimum.
        readonly property int rowWidth: Math.max(Style.space(190),
          Math.ceil(barMenuMetrics.advanceWidth) + Style.space(22) + Style.space(12) * 2 + root.menuPad * 2 + Style.space(12))
        readonly property int subRowWidth: Math.max(Style.space(170),
          Math.ceil(barSubMetrics.advanceWidth) + Style.space(22) + Style.space(12) * 2 + root.menuPad * 2 + Style.space(12))

        TextMetrics {
          id: barMenuMetrics
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          text: DockConfig.longestLabel(DockConfig.barMenuLabels(barMenu.rows))
        }

        TextMetrics {
          id: barSubMetrics
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          text: DockConfig.longestLabel(DockConfig.barSubmenuLabels(barMenu.rows))
        }

        function close() {
          barSubClose.stop()
          barMenu.openSection = ""
          barMenu.visible = false
        }
        function openAt(x, y) {
          barMenu.pointX = x
          barMenu.pointY = y
          barMenu.openSection = ""
          barMenu.visible = true
        }
        // The pointer is on a row: a section opens its submenu, any other
        // row closes the one open. Leaving a row toward the submenu must not
        // close it, so a close waits a moment and entering the submenu
        // cancels it.
        function hoverRow(row, rowY) {
          if (row.children) {
            barSubClose.stop()
            barMenu.openRowY = rowY
            barMenu.openSection = row.label
          } else if (barMenu.openSection !== "") {
            barSubClose.restart()
          }
        }

        Timer {
          id: barSubClose
          interval: 250
          onTriggered: barMenu.openSection = ""
        }

        grabFocus: true
        visible: false
        color: "transparent"
        anchor.window: panel
        anchor.adjustment: PopupAdjustment.Slide
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.onAnchoring: {
          // Beside the bar at the pointer (DockPlacement.alongBar, .beside).
          var bounds = { width: panel.width, height: panel.height }
          var at = DockPlacement.beside(panel.edge,
            DockPlacement.alongBar(panel.edge, { x: barMenu.pointX, y: barMenu.pointY, width: 0, height: 0 }, panel.geo.bar),
            { width: barMenu.implicitWidth, height: barMenu.implicitHeight }, bounds, barMenu.menuMargin, root.menuShadow, panel.popupGap)
          anchor.rect.x = Math.round(at.x)
          anchor.rect.y = Math.round(at.y)
        }

        implicitWidth: rowWidth + root.menuShadow * 2
        implicitHeight: barMenuLoader.implicitHeight + root.menuPad * 2 + root.menuShadow * 2

        onVisibleChanged: {
          revealState.set("barMenu", barMenu.visible || barSubMenu.visible)
          if (!barMenu.visible) barMenu.openSection = ""
        }
        onClosed: barMenu.close()

        RectangularShadow {
          anchors.fill: barFrame
          radius: barFrame.radius
          blur: root.menuShadow
          offset.y: Style.space(4)
          spread: 0
          color: Qt.rgba(0, 0, 0, 0.6)
        }

        Rectangle {
          id: barFrame
          anchors.fill: parent
          anchors.margins: root.menuShadow
          radius: root.menuRadius
          color: root.colPopupBackground
          border.width: Style.normalBorderWidth
          border.color: root.colHairline

          Loader {
            id: barMenuLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.menuPad
            sourceComponent: barMenuList
            onLoaded: {
              item.rows = Qt.binding(function () { return barMenu.rows })
              item.openLabel = Qt.binding(function () { return barMenu.openSection })
              item.rowsTop = Qt.binding(function () { return root.menuShadow + root.menuPad })
              item.mirrored = Qt.binding(function () { return panel.edge.right })
            }

            Connections {
              target: barMenuLoader.item
              ignoreUnknownSignals: true
              function onHovered(row, y) { barMenu.hoverRow(row, y) }
              function onChosen(row) { barMenu.choose(row) }
            }
          }
        }

        // A row was clicked: write its setting, or open the Settings window.
        // Close first so the menu never lingers over the window it opens.
        function choose(row) {
          if (row.enabled === false) return
          barMenu.close()
          if (row.action === "settings") root.openSettings(panel.screen)
          else dockSettings.apply({ type: "setSettings", patch: row.patch })
        }
      }

      // The submenu: a popup of its own, anchored to the Bar menu, level
      // with the section row it belongs to, on its right (or its left when
      // the screen has no room).
      PopupWindow {
        id: barSubMenu

        grabFocus: true
        visible: barMenu.visible && barMenu.openRows.length > 0
        color: "transparent"
        anchor.window: barMenu
        anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
        // On the right Dock the submenu opens on the menu's left.
        readonly property var opening: DockPlacement.submenu(panel.edge, barMenu.implicitWidth, root.menuShadow)
        anchor.edges: barSubMenu.opening.opensLeft ? Edges.Top | Edges.Left : Edges.Top | Edges.Right
        anchor.gravity: barSubMenu.opening.opensLeft ? Edges.Bottom | Edges.Left : Edges.Bottom | Edges.Right
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.onAnchoring: {
          // Frame to frame: the submenu's frame starts where the menu's ends
          // (or ends where its starts), and its first row lines up with the section's.
          anchor.rect.x = barSubMenu.opening.x
          anchor.rect.y = barMenu.openRowY - root.menuPad - root.menuShadow
        }

        implicitWidth: barMenu.subRowWidth + root.menuShadow * 2
        implicitHeight: barSubLoader.implicitHeight + root.menuPad * 2 + root.menuShadow * 2

        onVisibleChanged: {
          revealState.set("barMenu", barMenu.visible || barSubMenu.visible)
          if (visible) barSubMenu.anchor.updateAnchor()
        }
        onImplicitHeightChanged: if (visible) barSubMenu.anchor.updateAnchor()

        // The anchor reads openRowY when it is computed, and the popup stays up
        // while the pointer moves from one section to another: a section with
        // as many rows as the last changes neither visibility nor height, so
        // without this the submenu would stay level with the old row.
        Connections {
          target: barMenu
          function onOpenRowYChanged() {
            if (barSubMenu.visible) barSubMenu.anchor.updateAnchor()
          }
        }

        HoverHandler {
          onHoveredChanged: if (hovered) barSubClose.stop()
        }

        RectangularShadow {
          anchors.fill: barSubFrame
          radius: barSubFrame.radius
          blur: root.menuShadow
          offset.y: Style.space(4)
          spread: 0
          color: Qt.rgba(0, 0, 0, 0.6)
        }

        Rectangle {
          id: barSubFrame
          anchors.fill: parent
          anchors.margins: root.menuShadow
          radius: root.menuRadius
          color: root.colPopupBackground
          border.width: Style.normalBorderWidth
          border.color: root.colHairline

          Loader {
            id: barSubLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.menuPad
            sourceComponent: barMenuList
            onLoaded: {
              item.rows = Qt.binding(function () { return barMenu.openRows })
              item.openLabel = ""
              item.rowsTop = 0
            }

            Connections {
              target: barSubLoader.item
              ignoreUnknownSignals: true
              function onChosen(row) { barMenu.choose(row) }
            }
          }
        }
      }

      // The rows of a Bar menu popup (the menu, or a submenu): a column of
      // rows with a divider before each new group. `hovered(row, y)` says
      // where the pointer is (y in the popup window); `chosen(row)` is a
      // click on a row that is not a section.
      Component {
        id: barMenuList

        Column {
          id: barList
          property var rows: []
          property string openLabel: ""
          property real rowsTop: 0
          // The Bar menu on the right Dock: a section's chevron points left
          // from the left edge, where the submenu opens.
          property bool mirrored: false
          signal hovered(var row, real y)
          signal chosen(var row)

          Repeater {
            model: barList.rows

            delegate: Item {
              id: barRow
              required property var modelData
              required property int index

              readonly property bool newGroup: barRow.index > 0 && barList.rows[barRow.index - 1].group !== barRow.modelData.group
              readonly property bool isSection: !!barRow.modelData.children
              readonly property bool live: barRow.modelData.enabled !== false
              readonly property bool open: barRow.isSection && barRow.modelData.label === barList.openLabel

              width: barList.width
              height: root.menuRowHeight + (barRow.newGroup ? root.menuPad * 2 + 1 : 0)

              Rectangle {
                visible: barRow.newGroup
                anchors.top: parent.top
                anchors.topMargin: root.menuPad
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: root.colHairline
              }

              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: root.menuRowHeight
                radius: root.menuRowRadius
                color: (barRowMouse.containsMouse && barRow.live) || barRow.open
                  ? Style.hoverFillFor(root.colForeground, previewPopup.accentColor)
                  : "transparent"

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: barRow.modelData.checked ? "\u2713" : ""
                  color: previewPopup.textColor
                  opacity: barRow.live ? 1 : 0.4
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: barRow.isSection && !barList.mirrored ? sectionChevron.left : parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12) + Style.space(22)
                  anchors.rightMargin: Style.space(12)
                  elide: Text.ElideRight
                  text: barRow.modelData.label
                  color: previewPopup.textColor
                  opacity: barRow.live ? 1 : 0.4
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                // A section's chevron, pointing at its submenu: at the right
                // edge, or in the check's column at the left when mirrored (a
                // section is never checked, so the two share it).
                Text {
                  textFormat: Text.PlainText
                  id: sectionChevron
                  visible: barRow.isSection
                  x: barList.mirrored ? Style.space(12) : parent.width - width - Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: barList.mirrored ? "\u25C2" : "\u25B8"
                  color: previewPopup.textColor
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: barRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: barRow.live ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onEntered: barList.hovered(barRow.modelData, barList.rowsTop + barRow.y + parent.y)
                  // A section also opens on a click, for a pointer that
                  // never "enters" (touch, a keyboard-driven one).
                  onClicked: {
                    if (barRow.isSection) barList.hovered(barRow.modelData, barList.rowsTop + barRow.y + parent.y)
                    else barList.chosen(barRow.modelData)
                  }
                }
              }
            }
          }
        }
      }

      // The context menu (docs/SPEC.md "Input": "Right click: menu with
      // exactly Pin/Unpin, New Window, Close Window. Pin is disabled on
      // Letter Tile Items"). One instance per monitor's panel, re-anchored
      // to whichever Item was right-clicked; DockModel.menuFor supplies
      // every row's enabled state from the Item alone, so this only turns
      // that into labels and the dispatch each row triggers on click.
      PopupWindow {
        id: contextMenu

        property var anchorItem: null
        property var menuItem: null
        // Set when opened from a Preview thumbnail (docs/SPEC.md "Input"):
        // the menu is then for that one Window and sits above the thumbnail.
        // It is anchored to the panel, not the Preview popup, using the
        // thumbnail's place worked out in panel coordinates.
        property var previewCell: null
        property string previewWindowId: ""
        // Where the pointer was, in panel coordinates: the menu's bottom-left
        // corner goes there, as in Windows 11.
        property real previewPointX: 0
        property real previewPointY: 0
        readonly property bool forPreview: contextMenu.previewWindowId !== ""
        readonly property var anchorWindow: contextMenu.forPreview ? panel
          : (contextMenu.anchorItem ? contextMenu.anchorItem.QsWindow.window : null)
        readonly property int menuMargin: Style.spacing.xs
        // Sized to its longest row, since app actions ("New Private Window")
        // and window rows ("Move to scratchpad") vary; see barMenu.rowWidth.
        readonly property int rowWidth: Math.max(Style.space(160),
          Math.ceil(contextMenuMetrics.advanceWidth) + Style.space(12) * 2 + root.menuPad * 2 + Style.space(12)
          + (contextMenu.rows.some(function (r) { return r.icon || r.glyph }) ? Style.space(24) : 0))

        TextMetrics {
          id: contextMenuMetrics
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          text: DockConfig.longestLabel(contextMenu.rows)
        }

        // Rows in three groups, divided in the menu: App rows (Pin/Unpin, New
        // Window and the App's own desktop actions, e.g. "New Private
        // Window"), Window-state rows for a Window Item (DockModel.windowActions),
        // and Close Window. DockModel.menuFor supplies each row's enabled
        // state from the Item alone.
        readonly property var rows: {
          if (contextMenu.forPreview) {
            // Live, so a state that changes while the menu is open (or a
            // peek being put back) is reflected in the labels.
            let win = previewPopup.windowFor(contextMenu.previewWindowId)
            let previewRows = []
            let winStates = DockModel.windowActions(win)
            for (let s = 0; s < winStates.length; s++) {
              previewRows.push({
                label: winStates[s].label,
                enabled: true,
                group: 1,
                // Choosing a state row keeps the peeked Window focused, as a
                // click on the thumbnail does, instead of the peek being put back.
                trigger: (function (id) { return function () { previewState.send({ type: "menuRowChosen" }); root.runWindowAction(id, win.id) } })(winStates[s].id),
              })
            }
            previewRows.push({
              label: "Close window",
              glyph: "\u{f0156}",
              enabled: true,
              group: 2,
              trigger: function () { root.closeWindow(win.id) },
            })
            return previewRows
          }
          var item = contextMenu.menuItem
          if (!item) return []
          var menu = DockModel.menuFor(item)
          var appId = root.menuAppId(item)
          // A Pin with no Windows, as in Windows 11: the App's own actions,
          // then a row with its icon and name that starts it, then
          // "Unpin from taskbar".
          if (item.kind === "pin") {
            let pinRows = []
            let pinActions = item.app && item.app.actions ? item.app.actions : []
            for (let a = 0; a < pinActions.length; a++) {
              pinRows.push({
                label: pinActions[a].name,
                enabled: true,
                group: 0,
                trigger: (function (action) { return function () { action.execute() } })(pinActions[a]),
              })
            }
            if (item.app) {
              pinRows.push({
                label: root.pinTooltipText(item),
                icon: item.app.icon,
                enabled: true,
                group: 1,
                trigger: function () { root.launchApp(item.app) },
              })
            }
            pinRows.push({
              label: "Unpin from taskbar",
              glyph: "\u{f0404}",
              enabled: true,
              group: 1,
              trigger: function () { root.togglePin(appId, true) },
            })
            return pinRows
          }
          var list = []
          var appActions = item.app && item.app.actions ? item.app.actions : []
          for (let i = 0; i < appActions.length; i++) {
            list.push({
              label: appActions[i].name,
              enabled: true,
              group: 0,
              trigger: (function (action) { return function () { action.execute() } })(appActions[i]),
            })
          }
          if (item.kind === "window" && !(item.count > 1)) {
            let states = DockModel.windowActions(item.window)
            for (let j = 0; j < states.length; j++) {
              list.push({
                label: states[j].label,
                enabled: true,
                group: 1,
                trigger: (function (id) { return function () { root.runWindowAction(id, item.window.id) } })(states[j].id),
              })
            }
          }
          // As in Windows 11: the App's icon and name (starts another
          // instance), then Pin to / Unpin from taskbar. A Letter Tile
          // Window has no App, so it has neither.
          if (item.app) {
            list.push({
              label: root.pinTooltipText(item),
              icon: item.app.icon,
              enabled: menu.canLaunch,
              group: 2,
              trigger: function () { root.launchApp(item.app) },
            })
            list.push({
              label: menu.pinned ? "Unpin from taskbar" : "Pin to taskbar",
              glyph: menu.pinned ? "\u{f0404}" : "\u{f0403}",
              enabled: menu.canPin,
              group: 2,
              trigger: function () { root.togglePin(appId, menu.pinned) },
            })
          }
          // A Group Item's menu acts on the whole group: the window-state
          // rows are left out and Close closes every Window in it.
          var grouped = item.count > 1
          list.push({
            label: grouped ? "Close all windows" : "Close window",
            glyph: "\u{f0156}",
            enabled: menu.canClose,
            group: 3,
            trigger: function () {
              var windows = grouped ? item.windows : [item.window]
              for (let w = 0; w < windows.length; w++) root.closeWindow(windows[w].id)
            },
          })
          return list
        }

        function close() { contextMenu.visible = false }

        // The menu stays open until a row is chosen, an outside click closes
        // it (the focus grab below), or the pointer leaves it: leaving only
        // counts once the pointer has actually been on the menu
        // (enteredMenu), so one that is still travelling up from the
        // right-clicked Item never closes it, however long that takes.
        // Leaving closes after hideDelayMs, the same delay the Dock's own
        // auto-hide uses, so a brief crossing between rows doesn't.
        readonly property bool hoveringMenu: menuHover.hovered
        property bool enteredMenu: false

        // Without this, the popup renders on top but never actually
        // becomes the surface Hyprland routes pointer input to — hover
        // and clicks fall through to whatever's underneath, and any real
        // click reads as "outside" to the focus grab below.
        grabFocus: true

        visible: false
        color: "transparent"
        implicitWidth: contextMenu.rowWidth + root.menuShadow * 2
        implicitHeight: menuColumn.implicitHeight + root.menuPad * 2 + root.menuShadow * 2

        onVisibleChanged: {
          revealState.set("menu", contextMenu.visible)
          contextMenu.enteredMenu = false
          menuLeaveTimer.stop()
          previewState.send({ type: "menuVisible", visible: contextMenu.visible, forPreview: contextMenu.forPreview })
        }

        onHoveringMenuChanged: {
          if (contextMenu.hoveringMenu) {
            contextMenu.enteredMenu = true
            menuLeaveTimer.stop()
          } else if (contextMenu.visible && contextMenu.enteredMenu) {
            menuLeaveTimer.restart()
          }
        }

        Timer {
          id: menuLeaveTimer
          interval: root.hideDelayMs
          onTriggered: contextMenu.close()
        }

        // Outside-click dismissal: grabFocus's own compositor grab already
        // dismisses the popup on an outside click; onClosed is the signal
        // it fires when that happens, so this only needs to mirror that
        // into `visible`. A second, separate HyprlandFocusGrab here (as
        // PopupCard uses, for a popup that does *not* set grabFocus)
        // fought this one and cleared it the instant it opened.
        onClosed: contextMenu.close()

        anchor {
          id: menuAnchor
          window: contextMenu.anchorWindow
          adjustment: PopupAdjustment.Slide
          edges: Edges.Top | Edges.Left
          gravity: Edges.Bottom | Edges.Right
          rect.width: 1
          rect.height: 1

          onAnchoring: {
            if (contextMenu.forPreview) {
              let px = Math.max(contextMenu.menuMargin,
                Math.min(contextMenu.previewPointX, panel.width - contextMenu.implicitWidth - contextMenu.menuMargin))
              menuAnchor.rect.x = Math.round(px - root.menuShadow)
              menuAnchor.rect.y = Math.round(Math.max(contextMenu.menuMargin, contextMenu.previewPointY - contextMenu.implicitHeight + root.menuShadow))
              return
            }
            if (!contextMenu.anchorItem || !contextMenu.anchorWindow) return
            var target = contextMenu.anchorItem
            var popupWidth = contextMenu.implicitWidth
            var popupHeight = contextMenu.implicitHeight
            // Beside the Item, on the side facing into the screen
            // (DockPlacement.beside), in the anchor window's own coordinates.
            var origin = contextMenu.anchorWindow.contentItem.mapFromItem(target, 0, 0)
            var point = DockPlacement.beside(panel.edge,
              DockPlacement.alongBar(panel.edge, { x: origin.x, y: origin.y, width: target.width, height: target.height }, panel.geo.bar),
              { width: popupWidth, height: popupHeight },
              { width: contextMenu.anchorWindow.width, height: contextMenu.anchorWindow.height },
              contextMenu.menuMargin, root.menuShadow, panel.popupGap)
            menuAnchor.rect.x = Math.round(point.x)
            menuAnchor.rect.y = Math.round(point.y)
          }
        }

        RectangularShadow {
          anchors.fill: menuFrame
          radius: menuFrame.radius
          blur: root.menuShadow
          offset.y: Style.space(4)
          spread: 0
          color: Qt.rgba(0, 0, 0, 0.6)
        }

        Rectangle {
          id: menuFrame
          anchors.fill: parent
          anchors.margins: root.menuShadow
          radius: root.menuRadius
          color: root.colPopupBackground
          border.width: Style.normalBorderWidth
          border.color: root.colHairline

          HoverHandler {
            id: menuHover
          }

          Column {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.menuPad

            Repeater {
              model: contextMenu.rows

              delegate: Item {
                id: menuRow
                required property var modelData
                required property int index

                readonly property bool newGroup: index > 0 && contextMenu.rows[index - 1].group !== modelData.group

                width: menuColumn.width
                height: root.menuRowHeight + (newGroup ? root.menuPad * 2 + 1 : 0)

                Rectangle {
                  visible: menuRow.newGroup
                  anchors.top: parent.top
                  anchors.topMargin: root.menuPad
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: 1
                  color: root.colHairline
                }

                Rectangle {
                  id: menuRowBody
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: root.menuRowHeight
                  radius: root.menuRowRadius
                  // containsMouse, not a HoverHandler, to match Button.qml's
                  // own hover-fill convention.
                  color: menuRow.modelData.enabled && rowMouse.containsMouse
                    ? Style.hoverFillFor(root.colForeground, previewPopup.accentColor)
                    : "transparent"

                  // The App's icon, or a glyph, for the rows that have one.
                  Item {
                    id: menuRowIcon
                    visible: !!menuRow.modelData.icon || !!menuRow.modelData.glyph
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(16)
                    height: Style.space(16)

                    Image {
                      visible: !!menuRow.modelData.icon && source.toString() !== ""
                      anchors.fill: parent
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      sourceSize.width: width * Screen.devicePixelRatio
                      sourceSize.height: height * Screen.devicePixelRatio
                      source: menuRow.modelData.icon ? root.iconSource(menuRow.modelData.icon) : ""
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: !!menuRow.modelData.glyph
                      anchors.centerIn: parent
                      text: menuRow.modelData.glyph || ""
                      color: previewPopup.textColor
                      font.family: "JetBrainsMono Nerd Font"
                      font.pixelSize: Style.space(14)
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(12) + (menuRowIcon.visible ? Style.space(16) + Style.space(8) : 0)
                    anchors.rightMargin: Style.space(12)
                    elide: Text.ElideRight
                    text: menuRow.modelData.label
                    color: menuRow.modelData.enabled ? previewPopup.textColor : root.colMuted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: menuRow.modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      menuRow.modelData.trigger()
                      contextMenu.close()
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
