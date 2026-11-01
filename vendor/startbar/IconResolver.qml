// An App's icon, as an Image source, for the Dock and the Start menu
// (docs/SPEC.md "What the Dock shows"). Quickshell.iconPath(name, true)
// remembers a miss until the shell restarts, so an icon installed after its
// App was first looked up (a package installed while the shell runs) would
// stay blank. On a miss this searches the icon directories itself
// (DockIcons.js builds the command and picks the file) and hands back the file
// it finds; until then, or if there is none, source() is "" and the caller
// draws its fallback. One instance serves everything that draws icons, so a
// name is searched for once however many places show it.
//
// `files` is name -> path and, like `tries` and `last`, is reassigned and
// never edited in place, so a binding that called source() updates.
import QtQuick
import Quickshell
import Quickshell.Io
import "DockIcons.js" as DockIcons

Item {
  id: resolver

  visible: false

  property var files: ({})
  property var tries: ({})
  property var last: ({})
  property var queue: []
  property string searching: ""
  // Bumped by the retry timer so every binding that called source() asks again.
  property int retryTick: 0

  function source(name) {
    if (!name) return ""
    resolver.retryTick // re-ask when the retry timer fires
    var found = Quickshell.iconPath(name, true)
    if (found) return found
    var file = resolver.files[name]
    if (file) return "file://" + file
    resolver.search(name)
    return ""
  }

  // True while the first search for `name` is queued or running, so a caller
  // can wait for it instead of drawing its fallback and swapping it a moment
  // later. False once that search is over, found or not (a retry later keeps
  // the fallback showing).
  function pending(name) {
    if (!name || !DockIcons.searchCommand(name)) return false
    resolver.files // re-ask when a search finds a file
    resolver.searching // and when one starts or ends
    resolver.tries // and when one is counted
    if (resolver.files[name]) return false
    return !resolver.tries[name] || resolver.searching === name
  }

  function search(name) {
    if (!DockIcons.shouldSearch(resolver.tries[name], resolver.last[name], Date.now())) return
    if (resolver.searching === name || resolver.queue.indexOf(name) >= 0) return
    if (!DockIcons.searchCommand(name)) return
    resolver.queue.push(name)
    Qt.callLater(resolver.next)
  }

  function next() {
    if (runner.running || resolver.queue.length === 0) return
    var name = resolver.queue.shift()
    resolver.searching = name
    var tries = Object.assign({}, resolver.tries)
    tries[name] = (tries[name] || 0) + 1
    resolver.tries = tries
    var last = Object.assign({}, resolver.last)
    last[name] = Date.now()
    resolver.last = last
    runner.command = DockIcons.searchCommand(name)
    runner.running = true
  }

  Process {
    id: runner
    stdout: StdioCollector {
      onStreamFinished: {
        var file = DockIcons.pickBest(text)
        var name = resolver.searching
        if (file) {
          let files = Object.assign({}, resolver.files)
          files[name] = file
          resolver.files = files
        } else if (resolver.tries[name] < DockIcons.MAX_TRIES) {
          retry.restart()
        }
      }
    }
    onRunningChanged: {
      if (running) return
      resolver.searching = ""
      resolver.next()
    }
  }

  // Nothing found yet: look again shortly (the install may still be running).
  Timer {
    id: retry
    interval: DockIcons.RETRY_MS + 250
    onTriggered: resolver.retryTick = resolver.retryTick + 1
  }
}
