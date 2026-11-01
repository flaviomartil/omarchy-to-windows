// The built-in Start menu's view (docs/SPEC.md "Start menu"), modelled on the
// Windows 11 one: search, a Pinned grid, an "All apps" A-Z list, Recommended
// (recently launched) apps, right-click to pin/unpin, and an account + power
// row. StartMenu.js decides everything; `model` is its state, `send(event)`
// runs a transition, and the timers and effects it asks for are carried out
// here (arm / perform). This Item only paints the state and reports what the
// pointer and keyboard did.
//
// It is an Item of the panel (a full-screen layer surface), not a popup
// window. A popup's keyboard grab needs a recent click inside our own
// window, which a menu opened by hover or by the keyboard command doesn't
// have, so the compositor refused it and typing went to whatever window was
// focused. The panel instead claims the keyboard itself while the menu is
// open (keyboardFocus on the panel), the way Omarchy's own menu does.
//
// Events come in through send(): the panel sends the Start button's
// (buttonClick, buttonHover) and the keyboard command (command) and
// itemHovered when the pointer reaches another Item; dismiss when the
// click-away catcher is pressed. `open` and `hoverMode` are read-only.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "StartMenu.js" as StartMenu
import "DockPlacement.js" as DockPlacement

Item {
  id: startMenu

  // What this needs from outside. The panel binds these where it
  // instantiates the menu; nothing here reaches for `root` or `panel`.
  required property var taskbar        // DockConfig taskbar view: startCommand, startHoverOpen, alignment, barHeight
  required property var edge           // DockGeometry.edge(): which edge of the screen the Dock is on
  required property real dockGap       // the space between the card and the bar
  required property var settings       // dockSettings: startPins, recentApps, startPlaces, pins, apply(intent)
  property var scheme: null            // DockConfig.schemeColors: a fixed dark/light palette, null to follow the theme
  readonly property color colBackground: scheme ? scheme.background : Color.popups.background
  property bool glassy: false          // Omarchy's Glassy bar: the card is see-through (Service.qml `glassy`)
  readonly property color colSurface: glassy ? Util.alpha(colBackground, Math.min(colBackground.a, 0.6)) : colBackground
  readonly property color colText: scheme ? scheme.foreground : Color.popups.text
  readonly property color colBorder: scheme ? scheme.border : Color.popups.border
  readonly property color colForeground: scheme ? scheme.foreground : Color.foreground
  readonly property color colAccent: scheme ? scheme.accent : Color.accent
  readonly property color colOnAccent: scheme ? scheme.background : Color.background
  required property real panelWidth
  required property real panelHeight
  required property real buttonX       // the Start button's x, for left-aligned icons
  required property real buttonY       // its y, for the left Dock
  required property bool buttonHovered // the pointer is on the Start button
  required property var icons          // IconResolver: icons.source(name) is an Image source
  signal launchRequested(var entry)    // launch this desktop entry
  signal togglePinRequested(string appId, bool pinned) // Pin/Unpin on the Dock
  signal dockHoldRequested(bool held)  // keep the Dock Revealed while the menu is up

  // --- State machine (StartMenu.js) ---------------------------------

  property var model: StartMenu.initial()
  // Pieces of `model` the view binds to. Every transition replaces
  // `model`, so anything bound to it directly would re-evaluate (and
  // re-create its list) on every event; these only notify when they
  // really change.
  readonly property string query: startMenu.model.query
  property var overlay: null
  readonly property bool open: startMenu.model.open
  // Opened by resting on the Start button rather than a click, and not
  // yet used: it closes once the pointer is on neither the button nor
  // the menu, and a click-away does not dismiss it. A keystroke or a
  // click on the search box ends it.
  readonly property bool hoverMode: startMenu.model.hover
  readonly property bool searching: StartMenu.isSearching(startMenu.model)
  readonly property bool showAll: startMenu.model.view === "all"
  readonly property bool showLetters: startMenu.model.letters
  readonly property string overlayKind: startMenu.overlay ? startMenu.overlay.kind : ""
  readonly property string navSection: startMenu.model.nav.section
  readonly property int navIndex: startMenu.model.nav.index
  readonly property string dragPinId: startMenu.model.drag.id
  readonly property int dragPinSlot: startMenu.model.drag.slot
  readonly property bool pointerAround: startMenu.buttonHovered || startMenuHover.hovered

  // What the state machine needs to know that its state does not.
  readonly property var context: ({
    command: startMenu.taskbar.startCommand,
    hoverOpen: startMenu.taskbar.startHoverOpen,
    results: startMenu.results,
    pinned: startMenu.pinnedApps,
    recent: startMenu.recentApps,
    allFlat: startMenu.catalog.allFlat,
    letterRows: startMenu.catalog.letterRows,
    startPinIds: startMenu.settings.startPins,
    dockPinIds: startMenu.settings.pins,
  })

  function send(event) {
    var result = StartMenu.transition(startMenu.model, event, startMenu.context)
    var before = startMenu.model
    startMenu.model = result.state
    if (result.state.overlay !== before.overlay) startMenu.overlay = result.state.overlay
    // Imperative, after the lists have followed the new query: the lists
    // reset their own highlight when their model changes, and a binding to
    // an unchanged index would not put it back.
    resultList.currentIndex = result.state.resultIndex
    allList.currentIndex = result.state.allIndex
    startMenu.arm(result.timers)
    for (let i = 0; i < result.effects.length; i++) startMenu.perform(result.effects[i])
    return result.handled
  }

  function arm(timers) {
    if (timers.hoverOpen === "stop") hoverOpenTimer.stop()
    else if (timers.hoverOpen === "start") hoverOpenTimer.restart()
    if (timers.leave === "stop") leaveTimer.stop()
    else if (timers.leave === "start") leaveTimer.restart()
  }

  function perform(effect) {
    switch (effect.type) {
    case "holdDock": startMenu.dockHoldRequested(effect.held); break
    case "setQuery": searchInput.text = effect.text; break
    case "focusSearch":
      if (effect.deferred) Qt.callLater(function () { searchInput.forceActiveFocus() })
      else searchInput.forceActiveFocus()
      break
    case "scrollPinned": pinnedGrid.positionViewAtIndex(effect.index, GridView.Contain); break
    case "scrollAll":
      allList.positionViewAtIndex(effect.index, effect.position === "beginning" ? ListView.Beginning : ListView.Contain)
      break
    case "launch": startMenu.launchRequested(effect.app.entry); break
    case "apply": startMenu.settings.apply(effect.intent); break
    case "run": Quickshell.execDetached(["bash", "-lc", effect.command]); break
    case "open": Quickshell.execDetached(StartMenu.openCommand(effect.path)); break
    case "togglePin": startMenu.togglePinRequested(effect.appId, effect.pinned); break
    }
  }

  function keyName(key) {
    if (key === Qt.Key_Left) return "left"
    if (key === Qt.Key_Right) return "right"
    if (key === Qt.Key_Up) return "up"
    if (key === Qt.Key_Down) return "down"
    if (key === Qt.Key_Return || key === Qt.Key_Enter) return "enter"
    if (key === Qt.Key_Escape) return "escape"
    return "other"
  }

  Timer {
    id: hoverOpenTimer
    interval: StartMenu.HOVER_OPEN_DELAY_MS
    onTriggered: startMenu.send({ type: "hoverOpenFired" })
  }

  Timer {
    id: leaveTimer
    interval: StartMenu.LEAVE_DELAY_MS
    onTriggered: startMenu.send({ type: "leaveFired", pointerAround: startMenu.pointerAround })
  }

  // --- What the menu lists ------------------------------------------

  readonly property int menuMargin: Style.spacing.xs
  readonly property var allApps: {
    var values = DesktopEntries.applications.values
    var list = []
    for (let i = 0; i < values.length; i++) {
      let entry = values[i]
      list.push({
        id: entry.id,
        name: entry.name || entry.id,
        genericName: entry.genericName || "",
        keywords: entry.keywords || [],
        noDisplay: !!entry.noDisplay,
        icon: entry.icon,
        entry: entry,
      })
    }
    return list
  }
  readonly property var catalog: StartMenu.catalog(startMenu.allApps)
  readonly property var pinnedApps: StartMenu.resolveApps(startMenu.catalog, startMenu.settings.startPins)
  readonly property var recentApps: StartMenu.resolveApps(startMenu.catalog, startMenu.settings.recentApps)
  readonly property var results: StartMenu.filterApps(startMenu.allApps, startMenu.query)
  // Places column on the left (Home, Documents, Downloads...): from the
  // user's XDG folders or a `startPlaces` list (StartMenu.effectivePlaces).
  property string userDirsText: ""
  readonly property var places: StartMenu.effectivePlaces(startMenu.settings.startPlaces, startMenu.userDirsText, Quickshell.env("HOME") || "")
  readonly property real placesWidth: startMenu.places.length > 0 ? Style.space(150) : 0

  FileView {
    path: Quickshell.env("HOME") + "/.config/user-dirs.dirs"
    printErrors: false
    onLoaded: startMenu.userDirsText = text()
  }

  // Whether ~/.face exists, so the avatar never tries to load a missing file.
  property bool hasFace: false

  Process {
    running: true
    command: ["test", "-f", Quickshell.env("HOME") + "/.face"]
    onExited: function (exitCode) { startMenu.hasFace = exitCode === 0 }
  }

  Process {
    running: true
    command: ["getent", "passwd", Quickshell.env("USER") || ""]
    stdout: StdioCollector {
      onStreamFinished: startMenu.fullName = StartMenu.parseFullName(text, "")
    }
  }

  readonly property string userName: {
    var name = Quickshell.env("USER") || ""
    return name.length > 0 ? name.charAt(0).toUpperCase() + name.slice(1) : "User"
  }

  // Account: real name from the system account (falls back to the login).
  property string fullName: ""
  readonly property string accountName: startMenu.fullName.length > 0 ? startMenu.fullName : startMenu.userName

  // Drag to reorder a pinned app, as on the Dock: pinProbe is what the
  // pointer drags, pinGhost is drawn from it but held to the cells that hold
  // a pin, and the tiles between the two slots step aside (pinShift). The
  // state machine is told where the pointer is, in the grid's coordinates.
  function pinGridInfo() {
    return { width: pinnedGrid.width, height: pinnedGrid.height, cellWidth: pinnedGrid.cellWidth, cellHeight: pinnedGrid.cellHeight, contentY: pinnedGrid.contentY }
  }

  function pinDragMoved() {
    if (startMenu.dragPinId === "") return
    var grid = startMenu.pinGridInfo()
    var centre = pinnedGrid.mapFromItem(pinProbe.parent, pinProbe.x + pinProbe.width / 2, pinProbe.y + pinProbe.height / 2)
    startMenu.send({ type: "pinDragMove", point: centre, grid: grid })
    var topLeft = pinnedGrid.mapFromItem(pinProbe.parent, pinProbe.x, pinProbe.y)
    var held = StartMenu.clampPinGhost(topLeft, grid, startMenu.pinnedApps.length, StartMenu.PINNED_COLUMNS)
    var at = pinnedGrid.mapToItem(pinGhost.parent, held.x, held.y)
    pinGhost.x = at.x
    pinGhost.y = at.y
    startMenu.holdDrag = startMenu.model.drag
  }

  // The drag the tiles are drawn for. It outlives the drag until the new
  // order arrives (the saved list is read back from the config), so the tiles
  // do not return to the old order for a moment after a drop.
  property var holdDrag: ({ id: "", from: -1, slot: -1 })
  property bool pinDropping: false
  property string pinSettlingId: ""

  function pinShift(index) {
    return StartMenu.pinTileShift(startMenu.holdDrag, index, startMenu.pinGridInfo(), StartMenu.PINNED_COLUMNS)
  }

  // The grid's tiles, by app id, so a reorder moves them and rebuilds none of
  // them (they flashed as their icons loaded again).
  property var pinnedById: ({})

  function syncPinTiles() {
    var apps = startMenu.pinnedApps
    var byId = {}
    for (let n = 0; n < apps.length; n++) byId[apps[n].id] = apps[n]
    for (let r = pinKeys.count - 1; r >= 0; r--) {
      if (!byId[pinKeys.get(r).id]) pinKeys.remove(r)
    }
    startMenu.pinnedById = byId
    for (let i = 0; i < apps.length; i++) {
      if (i < pinKeys.count && pinKeys.get(i).id === apps[i].id) continue
      let at = -1
      for (let j = i + 1; j < pinKeys.count; j++) {
        if (pinKeys.get(j).id === apps[i].id) { at = j; break }
      }
      if (at >= 0) pinKeys.move(at, i, 1)
      else pinKeys.insert(i, { id: apps[i].id })
    }
  }

  ListModel { id: pinKeys }

  // True from a drop that saves a new order until it is read back: the ghost
  // stays on its slot meanwhile, so the tile is never seen in its old one.
  property bool pinAwaiting: false

  function releasePinHold() {
    if (startMenu.dragPinId !== "") return
    startMenu.pinDropping = true
    startMenu.holdDrag = ({ id: "", from: -1, slot: -1 })
    if (startMenu.pinAwaiting) {
      startMenu.pinAwaiting = false
      pinGhost.visible = false
      startMenu.pinSettlingId = ""
    }
    Qt.callLater(function () { startMenu.pinDropping = false })
  }

  onPinnedAppsChanged: {
    startMenu.pinDropping = true
    startMenu.syncPinTiles()
    startMenu.releasePinHold()
  }
  Component.onCompleted: startMenu.syncPinTiles()

  Timer {
    id: pinHoldTimer
    interval: 800
    onTriggered: startMenu.releasePinHold()
  }

  // The drop: the ghost glides into the slot the app now has (or back to its
  // own, if the drop saves nothing), then gives way to the tile.
  function finishPinDrag(id) {
    var drag = startMenu.model.drag
    var slot = drag.slot >= 0 ? drag.slot : drag.from
    startMenu.pinSettlingId = id
    var cols = StartMenu.PINNED_COLUMNS
    var cell = pinnedGrid.mapToItem(pinGhost.parent, (slot % cols) * pinnedGrid.cellWidth,
      Math.floor(slot / cols) * pinnedGrid.cellHeight - pinnedGrid.contentY)
    pinSettleX.to = cell.x
    pinSettleY.to = cell.y
    pinGhost.scale = 1
    startMenu.pinAwaiting = drag.slot >= 0 && drag.slot !== drag.from
    pinGhostSettle.restart()
    startMenu.send({ type: "pinDragEnd" })
    pinHoldTimer.restart()
  }

  function openAppMenu(app, item, mouse) {
    var point = item.mapToItem(card, mouse.x, mouse.y)
    startMenu.send({
      type: "appMenu",
      app: app,
      x: Math.min(point.x, card.width - Style.space(200)),
      y: Math.min(point.y, card.height - Style.space(130)),
    })
  }

  // --- Geometry -----------------------------------------------------

  visible: startMenu.open
  // Zero-sized while closed, so the panel's input mask (which goes by
  // item geometry) takes nothing from the windows beneath.
  readonly property real fullWidth: Style.space(600) + startMenu.placesWidth
  // The space the Dock leaves: the height less a bar along the bottom or top.
  readonly property real fullHeight: Math.min(Style.space(640), Math.max(Style.space(240),
    DockPlacement.startMenuRoom(startMenu.edge, startMenu.panelHeight, startMenu.taskbar.barHeight, startMenu.menuMargin, startMenu.dockGap)))
  width: startMenu.open ? startMenu.fullWidth : 0
  height: startMenu.open ? startMenu.fullHeight : 0
  // Where the card stands: beside the Dock, lined up with the Start button
  // (left-aligned icons) or centred on the screen, and on screen
  // (DockPlacement.startMenu).
  readonly property var place: DockPlacement.startMenu({
    edge: startMenu.edge,
    alignment: startMenu.taskbar.alignment,
    button: { x: startMenu.buttonX, y: startMenu.buttonY },
    size: { width: startMenu.fullWidth, height: startMenu.fullHeight },
    panel: { width: startMenu.panelWidth, height: startMenu.panelHeight },
    barHeight: startMenu.taskbar.barHeight,
    margin: startMenu.menuMargin,
    gap: startMenu.dockGap,
  })
  x: startMenu.place.x
  y: startMenu.place.y

  RectangularShadow {
    visible: startMenu.open
    anchors.fill: card
    radius: card.radius
    blur: Style.space(14)
    offset.y: Style.space(4)
    color: Qt.rgba(0, 0, 0, 0.6)
  }

  Rectangle {
    id: card
    anchors.fill: parent
    radius: Math.max(Style.cornerRadius, Style.space(8))
    color: startMenu.colSurface
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(startMenu.colText, 0.12)
    clip: true

    HoverHandler {
      id: startMenuHover
      onHoveredChanged: startMenu.send({ type: "menuHover", hovered: hovered })
    }

    // A slight shadow lifts the search box off the menu.
    RectangularShadow {
      anchors.fill: searchBox
      radius: searchBox.radius
      blur: Style.space(6)
      offset.y: Style.space(1)
      color: Qt.rgba(0, 0, 0, 0.22)
    }

    Rectangle {
      id: searchBox
      anchors.top: parent.top
      anchors.left: placesPane.right
      anchors.right: parent.right
      anchors.margins: Style.spacing.xxl
      height: Style.space(34)
      // A pill, as in Windows 11. Style.cornerRadius follows Hyprland's
      // window rounding, which many setups (this one included) set to 0,
      // and a sharp search box looks out of place.
      radius: height / 2
      // Opaque (the faint tint laid on the menu's own colour, not left see-
      // through): the shadow behind it is a whole blurred shape, and under a
      // see-through box it would grey the inside of the box.
      color: Qt.tint(startMenu.colBackground, Util.alpha(startMenu.colText, 0.05))
      border.width: 1
      border.color: Util.alpha(startMenu.colText, 0.12)

      // In a hover-opened menu, clicking the search box is how you say
      // "I want to type": it takes the focus grab (and the keyboard).
      MouseArea {
        anchors.fill: parent
        z: 2
        enabled: startMenu.hoverMode
        propagateComposedEvents: true
        onPressed: function (mouse) {
          startMenu.send({ type: "searchPressed" })
          mouse.accepted = false
        }
      }

      // The magnifier is the Material Design "magnify" glyph (U+F0349)
      // from the Nerd Font Omarchy already uses for its own icons, so it
      // matches the rest of the desktop.
      Text {
        textFormat: Text.PlainText
        id: searchGlyph
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg + 2
        text: "\uDB80\uDF49"
        color: Util.alpha(startMenu.colText, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 4
      }

      Text {
        textFormat: Text.PlainText
        visible: searchInput.text.length === 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: searchGlyph.right
        anchors.leftMargin: Style.spacing.md
        text: "Search for apps"
        color: Util.alpha(startMenu.colText, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      // PlainField, not a TextInput, so Qt never reads the clipboard for it
      // (PlainText.js). Using the keyboard means you want the menu:
      // StartMenu.js ends hover mode on any key, then says whether it took
      // this one (otherwise the key goes into the box).
      PlainField {
        id: searchInput
        anchors.fill: parent
        anchors.leftMargin: searchGlyph.x + searchGlyph.width + Style.spacing.md
        anchors.rightMargin: Style.spacing.md
        focus: true
        maxLength: 256
        color: startMenu.colText
        fontFamily: Style.font.family
        fontPixelSize: Style.font.body
        interceptKey: function (event) {
          return startMenu.send({ type: "key", key: startMenu.keyName(event.key) })
        }
        onTextChanged: startMenu.send({ type: "queryChanged", text: searchInput.text })
      }
    }

    // Places: one click opens the folder in the default file manager.
    Item {
      id: placesPane
      anchors.top: parent.top
      anchors.bottom: footer.top
      anchors.left: parent.left
      width: startMenu.placesWidth
      visible: startMenu.placesWidth > 0

      Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.spacing.md
        spacing: 2

        Repeater {
          model: startMenu.places

          delegate: Rectangle {
            id: placeRow
            required property var modelData
            width: parent.width
            height: Style.space(38)
            radius: Style.cornerRadius
            color: placeMouse.containsMouse ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"

            Image {
              id: placeIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: width
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: startMenu.icons.source(placeRow.modelData.icon)
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: placeIcon.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: placeRow.modelData.label
              color: startMenu.colText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: placeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: startMenu.send({ type: "openPlace", path: placeRow.modelData.path })
            }
          }
        }
      }
    }

    Item {
      id: body
      anchors.top: searchBox.bottom
      anchors.topMargin: Style.space(22)
      anchors.bottom: footer.top
      anchors.left: placesPane.right
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.xl
      anchors.rightMargin: Style.spacing.xl

      // Search results.
      ListView {
        id: resultList
        visible: startMenu.searching
        anchors.fill: parent
        clip: true
        model: startMenu.results
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0

        delegate: Rectangle {
          id: resultRow
          required property var modelData
          required property int index
          width: resultList.width
          height: Style.space(44)
          radius: Style.cornerRadius
          color: (resultList.currentIndex === index || resultMouse.containsMouse)
            ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"

          Image {
            id: resultIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            height: width
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            source: resultRow.modelData.icon ? startMenu.icons.source(resultRow.modelData.icon) : ""
          }

          Text {
            textFormat: Text.PlainText
            anchors.left: resultIcon.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: resultRow.modelData.name
            color: startMenu.colText
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: resultMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (mouse) {
              if (mouse.button === Qt.RightButton) startMenu.openAppMenu(resultRow.modelData, resultMouse, mouse)
              else startMenu.send({ type: "launch", app: resultRow.modelData })
            }
          }
        }
      }

      // All apps: A-Z with letter headings.
      ListView {
        id: allList
        visible: !startMenu.searching && startMenu.showAll
        anchors.fill: parent
        clip: true
        model: startMenu.catalog.allFlat
        currentIndex: -1
        boundsBehavior: Flickable.StopAtBounds

        section.property: "letter"
        section.criteria: ViewSection.FullString
        section.delegate: Item {
          required property string section
          width: allList.width
          height: Style.space(36)

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: parent.section
            color: startMenu.colText
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // Click a letter heading for the A-Z jump grid.
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: startMenu.send({ type: "letters", open: true })
          }
        }

        header: Item {
          width: allList.width
          height: Style.space(28) + Style.spacing.md

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: allBackButton.verticalCenter
            text: "All"
            color: startMenu.colText
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 1
            font.bold: true
          }

          Rectangle {
            id: allBackButton
            anchors.top: parent.top
            anchors.right: parent.right
            width: backLabel.implicitWidth + Style.spacing.md * 2
            height: Style.space(28)
            radius: Math.max(Style.cornerRadius, Style.space(4))
            color: backMouse.containsMouse ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : Util.alpha(startMenu.colText, 0.04)
            border.width: 1
            border.color: Util.alpha(startMenu.colText, 0.15)

            Text {
              textFormat: Text.PlainText
              id: backLabel
              anchors.centerIn: parent
              text: "‹  Back"
              color: startMenu.colText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: backMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: startMenu.send({ type: "showView", view: "home" })
            }
          }
        }

        delegate: Rectangle {
          id: allRow
          required property var modelData
          required property int index
          width: allList.width
          height: Style.space(48)
          radius: Math.max(Style.cornerRadius, Style.space(6))
          color: (allMouse.containsMouse || allList.currentIndex === allRow.index)
            ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"

          Image {
            id: allIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            height: width
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            source: allRow.modelData.icon ? startMenu.icons.source(allRow.modelData.icon) : ""
          }

          Column {
            anchors.left: allIcon.right
            anchors.leftMargin: Style.spacing.xxl + Style.spacing.md
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter

            Text {
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              text: allRow.modelData.name
              color: startMenu.colText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              textFormat: Text.PlainText
              visible: text.length > 0
              width: parent.width
              elide: Text.ElideRight
              text: allRow.modelData.genericName || ""
              color: Util.alpha(startMenu.colText, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: allMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (mouse) {
              if (mouse.button === Qt.RightButton) startMenu.openAppMenu(allRow.modelData, allMouse, mouse)
              else startMenu.send({ type: "launch", app: allRow.modelData })
            }
          }
        }
      }

      // The A-Z jump grid: letters that have apps are lit, the rest dim.
      Rectangle {
        id: lettersOverlay
        visible: startMenu.showLetters && startMenu.showAll && !startMenu.searching
        anchors.fill: parent
        z: 5
        color: startMenu.colBackground

        MouseArea { anchors.fill: parent; onClicked: startMenu.send({ type: "letters", open: false }) }

        Text {
          textFormat: Text.PlainText
          anchors.top: parent.top
          anchors.topMargin: Style.spacing.md
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Jump to"
          color: Util.alpha(startMenu.colText, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Grid {
          anchors.centerIn: parent
          columns: 6
          spacing: Style.spacing.md

          Repeater {
            model: ["#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]

            delegate: Rectangle {
              id: letterCell
              required property string modelData
              readonly property bool present: startMenu.catalog.letterRows[letterCell.modelData] !== undefined
              width: Style.space(52)
              height: width
              radius: Style.cornerRadius
              color: letterCell.present && letterMouse.containsMouse
                ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent)
                : (letterCell.present ? Util.alpha(startMenu.colText, 0.08) : "transparent")

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: letterCell.modelData
                color: letterCell.present ? startMenu.colAccent : Util.alpha(startMenu.colText, 0.25)
                font.family: Style.font.family
                font.pixelSize: Style.font.body + 2
                font.bold: letterCell.present
              }

              MouseArea {
                id: letterMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: letterCell.present
                cursorShape: Qt.PointingHandCursor
                onClicked: startMenu.send({ type: "jumpTo", letter: letterCell.modelData })
              }
            }
          }
        }
      }

      // Home: Pinned grid and Recommended list.
      Item {
        id: home
        visible: !startMenu.searching && !startMenu.showAll
        anchors.fill: parent

        // The same row the All apps header uses, so the two line up.
        Item {
          id: homeHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(28)
        }

        Text {
          textFormat: Text.PlainText
          id: pinnedTitle
          anchors.verticalCenter: homeHeader.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          text: "Pinned"
          color: startMenu.colText
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 1
          font.bold: true
        }

        Rectangle {
          id: allAppsButton
          anchors.verticalCenter: homeHeader.verticalCenter
          anchors.right: parent.right
          width: allAppsLabel.implicitWidth + Style.spacing.md * 2
          height: Style.space(28)
          radius: Math.max(Style.cornerRadius, Style.space(4))
          color: allAppsMouse.containsMouse ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : Util.alpha(startMenu.colText, 0.04)
          border.width: 1
          border.color: Util.alpha(startMenu.colText, 0.15)

          Text {
            textFormat: Text.PlainText
            id: allAppsLabel
            anchors.centerIn: parent
            text: "All apps  ›"
            color: startMenu.colText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: allAppsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: startMenu.send({ type: "showView", view: "all" })
          }
        }

        GridView {
          id: pinnedGrid
          anchors.top: homeHeader.bottom
          anchors.topMargin: Style.spacing.md
          anchors.bottom: recommendedTitle.top
          anchors.bottomMargin: Style.spacing.md
          anchors.left: parent.left
          anchors.right: parent.right
          clip: true
          cellWidth: Math.floor(width / StartMenu.PINNED_COLUMNS)
          cellHeight: Style.space(92)
          model: pinKeys
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: pinnedTile
            required property string id
            required property int index
            // The app itself, looked up by id; it keeps the last one found
            // for the moment between it going and its tile going.
            readonly property var live: startMenu.pinnedById[pinnedTile.id]
            property var modelData: ({})
            onLiveChanged: if (pinnedTile.live) pinnedTile.modelData = pinnedTile.live
            Component.onCompleted: if (pinnedTile.live) pinnedTile.modelData = pinnedTile.live
            width: pinnedGrid.cellWidth
            height: pinnedGrid.cellHeight
            opacity: startMenu.dragPinId === pinnedTile.id || startMenu.pinSettlingId === pinnedTile.id ? 0 : 1

            // Tiles the dragged one has passed step aside by one slot, and a
            // pressed tile shrinks a little before it is lifted.
            property var shift: startMenu.pinShift(pinnedTile.index)
            property real shiftX: pinnedTile.shift.x
            property real shiftY: pinnedTile.shift.y
            Behavior on shiftX { enabled: !startMenu.pinDropping; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on shiftY { enabled: !startMenu.pinDropping; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            transform: Translate { x: pinnedTile.shiftX; y: pinnedTile.shiftY }
            scale: (pinnedMouse.pressedButtons & Qt.LeftButton) && startMenu.dragPinId === "" ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

            Rectangle {
              anchors.fill: parent
              anchors.margins: 2
              radius: Math.max(Style.cornerRadius, Style.space(6))
              color: (pinnedMouse.containsMouse || (startMenu.navSection === "pinned" && startMenu.navIndex === pinnedTile.index))
                ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"
            }

            Image {
              id: pinnedIcon
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.md
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(36)
              height: width
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: pinnedTile.modelData.icon ? startMenu.icons.source(pinnedTile.modelData.icon) : ""
            }

            Text {
              textFormat: Text.PlainText
              anchors.top: pinnedIcon.bottom
              anchors.topMargin: Style.spacing.xs
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: 4
              anchors.rightMargin: 4
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: pinnedTile.modelData.name
              color: startMenu.colText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: pinnedMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              // Left-drag a pin to reorder it: the ghost (a sibling of
              // the grid) follows the pointer, the tiles in between step
              // aside, and releasing writes the new order.
              preventStealing: true
              drag.target: pinProbe
              drag.threshold: 8
              // A drag still ends in a click event; this stops the drop
              // from also launching the app.
              property bool wasDragged: false

              onPressed: function (mouse) {
                pinnedMouse.wasDragged = false
                if (mouse.button !== Qt.LeftButton) {
                  pinnedMouse.drag.target = null
                  return
                }
                pinnedMouse.drag.target = pinProbe
                pinGhostSettle.stop()
                startMenu.pinSettlingId = ""
                pinHoldTimer.stop()
                var origin = pinnedTile.mapToItem(home, 0, 0)
                pinProbe.x = origin.x
                pinProbe.y = origin.y
                pinProbe.width = pinnedTile.width
                pinProbe.height = pinnedTile.height
                pinGhost.x = origin.x
                pinGhost.y = origin.y
                pinGhost.width = pinnedTile.width
                pinGhost.height = pinnedTile.height
                pinGhost.scale = 0.88
                pinGhost.app = pinnedTile.modelData
              }

              drag.onActiveChanged: {
                if (pinnedMouse.drag.active) {
                  pinnedMouse.wasDragged = true
                  startMenu.send({ type: "pinDragStart", id: pinnedTile.id })
                  startMenu.holdDrag = startMenu.model.drag
                  pinGhost.visible = true
                  pinGhost.scale = 1.15
                  startMenu.pinDragMoved()
                } else if (startMenu.dragPinId === pinnedTile.id) {
                  startMenu.finishPinDrag(pinnedTile.id)
                }
              }

              onClicked: function (mouse) {
                if (pinnedMouse.wasDragged) return
                if (mouse.button === Qt.RightButton) startMenu.openAppMenu(pinnedTile.modelData, pinnedMouse, mouse)
                else startMenu.send({ type: "launch", app: pinnedTile.modelData })
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: startMenu.pinnedApps.length === 0
            anchors.centerIn: parent
            text: "Right-click an app in All apps to pin it here"
            color: Util.alpha(startMenu.colText, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // What the pointer drags (pinnedMouse.drag.target above): invisible,
        // it goes wherever the pointer does. pinGhost is drawn from it.
        Item {
          id: pinProbe
          visible: false
          onXChanged: startMenu.pinDragMoved()
          onYChanged: startMenu.pinDragMoved()
        }

        // The drop: the ghost glides into its slot, then the tile shows again.
        ParallelAnimation {
          id: pinGhostSettle
          onFinished: {
            if (startMenu.pinAwaiting) return
            pinGhost.visible = false
            startMenu.pinSettlingId = ""
          }
          NumberAnimation { id: pinSettleX; target: pinGhost; property: "x"; duration: 120; easing.type: Easing.OutCubic }
          NumberAnimation { id: pinSettleY; target: pinGhost; property: "y"; duration: 120; easing.type: Easing.OutCubic }
        }

        // The icon of a drag: a little bigger than the tiles beside it,
        // following the pointer until it reaches the first or last slot.
        Item {
          id: pinGhost
          property var app: null
          visible: false
          z: 100
          opacity: 0.95
          scale: 1
          Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

          Image {
            anchors.top: parent.top
            anchors.topMargin: Style.spacing.md
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(36)
            height: width
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            source: pinGhost.app && pinGhost.app.icon ? startMenu.icons.source(pinGhost.app.icon) : ""
          }
        }

        Text {
          textFormat: Text.PlainText
          id: recommendedTitle
          anchors.bottom: recommendedGrid.top
          anchors.bottomMargin: Style.spacing.md
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          text: "Recommended"
          color: startMenu.colText
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 1
          font.bold: true
        }

        GridView {
          id: recommendedGrid
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(48) * 3
          clip: true
          cellWidth: Math.floor(width / StartMenu.RECENT_COLUMNS)
          cellHeight: Style.space(48)
          model: startMenu.recentApps
          interactive: false

          delegate: Item {
            id: recentTile
            required property var modelData
            required property int index
            width: recommendedGrid.cellWidth
            height: recommendedGrid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: 2
              radius: Math.max(Style.cornerRadius, Style.space(6))
              color: (recentMouse.containsMouse || (startMenu.navSection === "recent" && startMenu.navIndex === recentTile.index))
                ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"
            }

            Image {
              id: recentIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              height: width
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: recentTile.modelData.icon ? startMenu.icons.source(recentTile.modelData.icon) : ""
            }

            Column {
              anchors.left: recentIcon.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter

              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: recentTile.modelData.name
                color: startMenu.colText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              // The desktop entry's generic name ("Web Browser"), the
              // counterpart of Windows' "Welcome to Windows" line.
              Text {
                textFormat: Text.PlainText
                visible: text.length > 0
                width: parent.width
                elide: Text.ElideRight
                text: recentTile.modelData.genericName || ""
                color: Util.alpha(startMenu.colText, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: recentMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function (mouse) {
                if (mouse.button === Qt.RightButton) startMenu.openAppMenu(recentTile.modelData, recentMouse, mouse)
                else startMenu.send({ type: "launch", app: recentTile.modelData })
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: startMenu.recentApps.length === 0
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            anchors.top: parent.top
            text: "Apps you open from here show up here"
            color: Util.alpha(startMenu.colText, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // Account and power row.
    Rectangle {
      id: footer
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: Style.space(60)
      color: Util.alpha(startMenu.colText, 0.05)

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Util.alpha(startMenu.colText, 0.1)
      }

      // Clicking the account (avatar or name) opens Lock / Sign out.
      Rectangle {
        id: userButton
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        width: userNameText.x + userNameText.width + Style.spacing.md
        height: Style.space(44)
        radius: Style.cornerRadius
        color: userMouse.containsMouse || startMenu.overlayKind === "user" ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"

        MouseArea {
          id: userMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: startMenu.send({ type: "toggleOverlay", kind: "user" })
        }
      }

      Rectangle {
        id: avatar
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xl
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        height: width
        radius: width / 2
        color: startMenu.colAccent

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: startMenu.accountName.charAt(0).toUpperCase()
          color: startMenu.colOnAccent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Your picture, ~/.face, cropped to a circle; the initial above
        // shows when there isn't one.
        Item {
          anchors.fill: parent
          visible: faceImage.status === Image.Ready
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: avatarMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }

          Image {
            id: faceImage
            anchors.fill: parent
            source: startMenu.hasFace ? "file://" + Quickshell.env("HOME") + "/.face" : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
          }
        }

        Item {
          id: avatarMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          Rectangle { anchors.fill: parent; radius: width / 2 }
        }
      }

      Text {
        textFormat: Text.PlainText
        id: userNameText
        anchors.left: avatar.right
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: startMenu.accountName
        color: startMenu.colText
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Rectangle {
        id: powerButton
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xl
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(36)
        height: width
        radius: Style.cornerRadius
        color: powerMouse.containsMouse || startMenu.overlayKind === "power" ? Style.hoverFillFor(startMenu.colForeground, startMenu.colAccent) : "transparent"

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "⏻"
          color: startMenu.colText
          font.pixelSize: Style.font.body + 4
        }

        MouseArea {
          id: powerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: startMenu.send({ type: "toggleOverlay", kind: "power" })
        }
      }
    }

    // Click anywhere else closes an open overlay menu.
    MouseArea {
      anchors.fill: parent
      z: 20
      visible: startMenu.overlayKind !== ""
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: startMenu.send({ type: "closeOverlay" })
    }

    // Right-click menu on an app, and the power menu.
    Rectangle {
      id: overlayMenu
      z: 30
      visible: startMenu.overlayKind !== ""
      width: Style.space(190)
      height: overlayColumn.implicitHeight + Style.space(4) * 2
      radius: Math.max(Style.cornerRadius, Style.space(8))
      color: startMenu.colSurface
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(startMenu.colText, 0.12)
      readonly property bool system: startMenu.overlayKind === "power" || startMenu.overlayKind === "user"
      x: startMenu.overlayKind === "power" ? card.width - width - Style.spacing.md
        : (startMenu.overlayKind === "user" ? Style.spacing.md : (startMenu.overlay ? startMenu.overlay.x : 0))
      y: overlayMenu.system ? footer.y - height - Style.spacing.xs : (startMenu.overlay ? startMenu.overlay.y : 0)

      Column {
        id: overlayColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)

        Repeater {
          model: StartMenu.overlayRows(startMenu.overlay, startMenu.context)

          delegate: Rectangle {
            id: overlayRow
            required property var modelData
            width: overlayColumn.width
            height: Style.space(32)
            radius: Math.max(Style.cornerRadius, Style.space(4))
            color: overlayMouse.containsMouse ? Util.alpha(startMenu.colText, 0.08) : "transparent"

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: overlayRow.modelData.label
              color: startMenu.colText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: overlayMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // The row is data; `send` runs inside startMenu, so it
              // finishes even though closing the overlay changes this
              // Repeater's model and destroys this delegate.
              onClicked: startMenu.send({ type: "choose", row: overlayRow.modelData })
            }
          }
        }
      }
    }
  }
}
