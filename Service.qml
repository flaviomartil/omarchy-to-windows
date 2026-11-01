import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
  id: root
  property var shell: null
  property string windowAddress: ""
  property int monitorId: -1
  property int anchorX: 0
  property int anchorY: 0
  property bool buttonHovered: false
  property bool popupHovered: false
  property bool opened: false
  property bool keyboardMode: false
  readonly property var layouts: [
    [[0,0,6,12], [6,0,6,12]],
    [[0,0,4,12], [4,0,8,12]],
    [[0,0,4,12], [4,0,4,12], [8,0,4,12]],
    [[0,0,6,12], [6,0,6,6], [6,6,6,6]],
    [[0,0,6,6], [6,0,6,6], [0,6,6,6], [6,6,6,6]],
    [[0,0,3,12], [3,0,6,12], [9,0,3,12]]
  ]

  function close() {
    opening.stop()
    closing.stop()
    opened = false
    buttonHovered = false
    popupHovered = false
    keyboardMode = false
  }

  function choose(rect) {
    var address = windowAddress
    close()
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/omarchy-to-windows-window", "zone", "--window", address, "--rect"].concat(rect.map(String)))
  }

  Timer {
    id: opening
    interval: 450
    onTriggered: if (root.buttonHovered) root.opened = true
  }

  Timer {
    id: closing
    interval: 350
    onTriggered: if (!root.buttonHovered && !root.popupHovered) root.close()
  }

  IpcHandler {
    target: "io.github.flaviomartil.omarchy-to-windows"
    function enter(address: string, monitor: int, x: int, y: int): void {
      if (!/^0x[0-9a-fA-F]+$/.test(address)) return
      if (root.windowAddress !== address) root.close()
      root.windowAddress = address
      root.monitorId = monitor
      root.anchorX = x
      root.anchorY = y
      root.buttonHovered = true
      closing.stop()
      if (!root.opened) opening.restart()
    }
    function leave(address: string): void {
      if (root.windowAddress !== address) return
      root.buttonHovered = false
      opening.stop()
      if (!root.keyboardMode) closing.restart()
    }
    function open(): void {
      if (root.opened) root.close()
      else activeWindow.running = true
    }
    function hide(): void { root.close() }
    function state(): string {
      return JSON.stringify({opened: root.opened, address: root.windowAddress, monitor: root.monitorId})
    }
  }

  Process {
    id: activeWindow
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var win = JSON.parse(text)
          if (!/^0x[0-9a-fA-F]+$/.test(win.address || "")) return
          root.windowAddress = win.address
          root.monitorId = win.monitor
          root.anchorX = win.at[0] + win.size[0]
          root.anchorY = win.at[1]
          root.keyboardMode = true
          root.opened = true
        } catch (error) { console.error("Snap Layouts: " + error) }
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "closewindow" && "0x" + event.data === root.windowAddress) root.close()
      if (event.name === "workspace" || event.name === "focusedmon" || event.name === "fullscreen") root.close()
      if (event.name === "activewindowv2" && event.data && "0x" + event.data !== root.windowAddress) root.close()
    }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: panel
      required property var modelData
      readonly property var monitor: Hyprland.monitorFor(modelData)
      screen: modelData
      visible: root.opened && monitor && monitor.id === root.monitorId
      anchors { top: true; bottom: true; left: true; right: true }
      exclusiveZone: -1
      color: "transparent"
      WlrLayershell.namespace: "windows-11-snap-layouts"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.keyboardMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      mask: Region { item: root.keyboardMode ? outside : frame }

      onVisibleChanged: if (visible && root.keyboardMode) frame.forceActiveFocus()

      MouseArea {
        id: outside
        anchors.fill: parent
        enabled: root.keyboardMode
        onClicked: root.close()
      }

      Rectangle {
        id: frame
        width: 364
        height: 220
        x: Math.max(12, Math.min(panel.width - width - 12, root.anchorX - (panel.monitor?.lastIpcObject?.x || 0) - width))
        y: Math.max(12, Math.min(panel.height - height - 60, root.anchorY - (panel.monitor?.lastIpcObject?.y || 0) + 6))
        radius: 10
        color: "#292929"
        border.color: "#505050"
        Keys.onEscapePressed: root.close()

        HoverHandler {
          onHoveredChanged: {
            root.popupHovered = hovered
            if (hovered) closing.stop()
            else if (!root.keyboardMode) closing.restart()
          }
        }

        Text {
          textFormat: Text.PlainText
          x: 16; y: 12
          text: "Snap window"
          color: "#f3f3f3"
          font.family: "Inter"
          font.pixelSize: 13
        }

        Grid {
          x: 16; y: 40
          columns: 3
          spacing: 14
          Repeater {
            model: root.layouts
            Item {
              required property var modelData
              width: 100
              height: 72
              Repeater {
                model: parent.modelData
                Rectangle {
                  required property var modelData
                  x: modelData[0] / 12 * 100 + 1
                  y: modelData[1] / 12 * 72 + 1
                  width: modelData[2] / 12 * 100 - 3
                  height: modelData[3] / 12 * 72 - 3
                  radius: 3
                  color: hover.hovered || activeFocus ? "#60cdff" : "#606060"
                  border.color: hover.hovered || activeFocus ? "#b5e9ff" : "#888888"
                  Accessible.role: Accessible.Button
                  Accessible.name: "Snap to this position"
                  activeFocusOnTab: true
                  Keys.onReturnPressed: root.choose(modelData)
                  Keys.onSpacePressed: root.choose(modelData)
                  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: root.choose(parent.modelData) }
                }
              }
            }
          }
        }
      }
    }
  }
}
