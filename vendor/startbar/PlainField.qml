// A one-line text field that is not a native TextInput (PlainText.js says
// why: a TextInput reads the clipboard whenever it changes, with no size limit
// or deadline). It draws its own text and caret and takes the keys itself:
// typing, Backspace, Ctrl+U (clear), Enter, and Ctrl+V or Shift+Insert to
// paste, which asks wl-paste for at most 4 KiB and gives up after a second.
// No caret movement, selection or IME composition.
//
// `text` is read and written like a TextInput's. editingFinished fires on
// Enter and when focus leaves. `interceptKey`, if set, sees each key first
// and returns true when it took the key (the Start menu's own keys).
import QtQuick
import Quickshell.Io
import "PlainText.js" as PlainText

Item {
  id: field

  property string text: ""
  property color color: "white"
  property string fontFamily: ""
  property int fontPixelSize: 14
  property int maxLength: 1024
  property var interceptKey: null
  signal editingFinished()

  clip: true

  Text {
    textFormat: Text.PlainText
    id: typed
    anchors.verticalCenter: parent.verticalCenter
    // Scroll so the end (the caret) stays in view.
    x: Math.min(0, field.width - width - caret.width)
    text: field.text
    color: field.color
    font.family: field.fontFamily
    font.pixelSize: field.fontPixelSize
  }

  Rectangle {
    id: caret
    visible: field.activeFocus && blink.on
    anchors.verticalCenter: parent.verticalCenter
    x: typed.x + typed.width
    width: 1
    height: field.fontPixelSize + 4
    color: field.color
  }

  Timer {
    id: blink
    property bool on: true
    interval: 530
    running: field.activeFocus
    repeat: true
    onTriggered: blink.on = !blink.on
    onRunningChanged: blink.on = true
  }

  MouseArea {
    anchors.fill: parent
    onPressed: field.forceActiveFocus()
  }

  onActiveFocusChanged: if (!activeFocus) field.editingFinished()

  Process {
    id: pasteRunner
    command: PlainText.pasteCommand()
    stdout: StdioCollector {
      onStreamFinished: {
        var room = field.maxLength - field.text.length
        field.text = field.text + PlainText.cleanPaste(text, room)
      }
    }
  }

  function paste() {
    if (!pasteRunner.running) pasteRunner.running = true
  }

  Keys.onPressed: function (event) {
    if (field.interceptKey && field.interceptKey(event)) {
      event.accepted = true
      return
    }
    blink.on = true
    var ctrlOnly = event.modifiers === Qt.ControlModifier
    if ((ctrlOnly && event.key === Qt.Key_V) || (event.modifiers === Qt.ShiftModifier && event.key === Qt.Key_Insert)) {
      field.paste()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      field.editingFinished()
      event.accepted = true
      return
    }
    var held = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0
    var next = PlainText.applyKey(field.text, {
      key: event.key === Qt.Key_Backspace ? "backspace" : (event.key === Qt.Key_U ? "u" : "other"),
      ctrl: held,
      ctrlOnly: ctrlOnly,
      text: event.text
    }, field.maxLength)
    if (next !== null) {
      field.text = next
      event.accepted = true
    }
  }
}
