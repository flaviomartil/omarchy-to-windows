// Pure Preview logic (docs/SPEC.md "Input", "Grouping"; vocabulary in
// CONTEXT.md). No Quickshell or QML imports, so the exact same file loads as
// a JS import inside the shell and via `require` under Node for the test
// suite.
//
// The hover Preview, Peek and the Preview menu as one state machine, the way
// StartMenu.js does the Start menu: `transition(state, event, ctx)` returns
// `{ state, timers, effects }` and Service.qml only keeps the state, arms the
// timers, carries out the effects and paints. What it decides: which Item's
// Preview is up and when it opens and goes; which thumbnail is peeked and
// when the peek is applied, kept or put back; that a Preview's own menu holds
// the Preview up; and the order of commit, focus and close when a thumbnail
// is clicked.
//
// STATE (plain data, never mutated):
//   hovered     the Item under the pointer, or null
//   shown       the Item the Preview is up for, or null while closed
//   peekTarget  id of the thumbnail the pointer is on (a peek is pending or in
//               effect for it), or null
//   peekedId    id of the Window the peek currently shows
//   peeking     a peek has been applied and not yet restored or committed
//   menuOpen    the Preview's own menu (right click on a thumbnail) is up
//
// EVENTS (`type` plus fields):
//   hoverStart {item, enabled, dragging}, hoverEnd     an Item under the pointer
//   previewHover {hovered}                             the pointer is on the Preview
//   openFired, leaveFired                              the Preview's timers
//   dismiss                                            drop the Preview now
//   previewClosed                                      the Preview went away
//   thumbHover {window, hovered}, peekFired, peekRestoreFired
//   thumbPicked {window}                               a click on a thumbnail
//   thumbMenu {windowId}                               right click on a thumbnail
//   menuVisible {visible, forPreview}                  the Dock's Item menu opened or closed
//   menuRowChosen                                      a Preview menu state row was chosen
//
// CTX: { previewPeek, warp } (the settings of the same name).
//
// TIMERS: { open, leave, peek, peekRestore } -> "start" (restart) | "stop";
// absent = leave alone.
//
// EFFECTS (data for Service.qml to carry out, in order):
//   { type: "peek", id }          show that Window
//   { type: "restore" }           put back what the peek changed
//   { type: "commit" }            keep it: drop the saved state
//   { type: "focus", id, warp }   focus the Window picked

function initial() {
  return { hovered: null, shown: null, peekTarget: null, peekedId: "", peeking: false, menuOpen: false };
}

function patch(state, changes) {
  var next = {};
  for (var key in state) next[key] = state[key];
  for (var change in changes) next[change] = changes[change];
  return next;
}

function result(state, timers, effects) {
  return { state: state, timers: timers || {}, effects: effects || [] };
}

function unchanged(state) {
  return result(state);
}

// A peek that is no longer in effect, however it ended.
function peekOver(state) {
  return patch(state, { peeking: false, peekedId: "" });
}

function transition(state, event, ctx) {
  var shown;
  switch (event.type) {
  case "hoverStart":
    if (event.dragging || !event.enabled) return unchanged(state);
    // Hovering the shown Item again keeps it; any other Item closes the
    // Preview first, so its own opens afresh (and slides up) after the open
    // delay.
    if (state.shown && state.shown.key === event.item.key) {
      return result(patch(state, { hovered: event.item, shown: event.item }), { leave: "stop" });
    }
    return result(patch(state, { hovered: event.item, shown: null }), { leave: "stop", open: "start" });

  case "hoverEnd":
    return result(state, { open: "stop", leave: "start" });

  case "previewHover":
    return result(state, { leave: event.hovered ? "stop" : "start" });

  case "openFired":
    if (!state.hovered) return unchanged(state);
    return result(patch(state, { shown: state.hovered }));

  case "leaveFired":
    // A Preview's own menu keeps it up: the pointer is on the menu, not it.
    if (state.menuOpen) return unchanged(state);
    return result(patch(state, { shown: null }));

  case "dismiss":
    return result(patch(state, { shown: null }), { open: "stop", leave: "stop" });

  case "previewClosed":
    // The effect is decided from what was actually peeked, so a click that
    // has just committed is not followed by a restore, and Peek turned off
    // mid-hover still puts the peek back.
    return result(patch(peekOver(state), { peekTarget: null }), { peek: "stop", peekRestore: "stop" },
      state.peeking ? [{ type: "restore" }] : []);

  case "thumbHover":
    if (!ctx.previewPeek || !event.window || state.menuOpen) return unchanged(state);
    if (event.hovered) {
      return result(patch(state, { peekTarget: event.window.id }), { peekRestore: "stop", peek: "start" });
    }
    // Qt can report the next cell's enter before the previous cell's leave,
    // so a leave only counts if it is from the cell we think the pointer is
    // on; a stale one must not cancel the new cell's peek.
    if (state.peekTarget === event.window.id) {
      return result(patch(state, { peekTarget: null }), { peek: "stop", peekRestore: "start" });
    }
    return unchanged(state);

  case "peekFired":
    if (!state.peekTarget) return unchanged(state);
    return result(patch(state, { peeking: true, peekedId: state.peekTarget }), {}, [{ type: "peek", id: state.peekTarget }]);

  case "peekRestoreFired":
    return result(peekOver(state), {}, [{ type: "restore" }]);

  case "thumbPicked":
    return result(patch(peekOver(state), { shown: null, peekTarget: null }),
      { peek: "stop", open: "stop", leave: "stop" },
      [{ type: "commit" }, { type: "focus", id: event.window.id, warp: !!ctx.warp }]);

  case "thumbMenu":
    // The peek is left as it is while the menu is open: putting it back
    // changes focus and workspace, and that closes the menu. Only a peek of
    // some other Window is put back first.
    if (state.peeking && state.peekedId !== event.windowId) {
      return result(patch(peekOver(state), { peekTarget: null }), { peek: "stop", peekRestore: "stop" }, [{ type: "restore" }]);
    }
    return result(patch(state, { peekTarget: null }), { peek: "stop", peekRestore: "stop" });

  case "menuVisible":
    // Every open or close of the Dock's menu is heard, whichever menu it is,
    // so a Preview menu that was replaced by an Item menu without a close in
    // between cannot leave the Preview held up for good.
    var holds = !!event.visible && !!event.forPreview;
    // The Preview was held up while its menu was open; let it go.
    var released = !event.visible && !!event.forPreview;
    return result(patch(state, { menuOpen: holds }), released ? { leave: "start" } : {});

  case "menuRowChosen":
    // Choosing a state row keeps the peeked Window focused, as a click on
    // the thumbnail does, instead of the peek being put back.
    return result(peekOver(state), {}, [{ type: "commit" }]);
  }
  return unchanged(state);
}

// --- What is live -----------------------------------------------------------

function windowsOf(item) {
  return item.windows || [item.window];
}

// The shown Item as the Dock has it now, matched by Window id since a Group
// Item's key changes as Windows come and go, so a Window closed from the
// Preview drops out of it at once and the Preview closes with the last one.
function liveItem(shown, items) {
  if (!shown) return null;
  var ids = {};
  var shownWindows = windowsOf(shown);
  for (var i = 0; i < shownWindows.length; i++) ids[shownWindows[i].id] = true;
  for (var j = 0; j < items.length; j++) {
    if (items[j].kind !== "window") continue;
    var windows = windowsOf(items[j]);
    for (var k = 0; k < windows.length; k++) if (ids[windows[k].id]) return items[j];
  }
  return null;
}

// The ids of the thumbnails to draw. The previous array comes back while the
// set is unchanged: the cells are keyed by it, and a peek moves focus, which
// rebuilds the Items; rebuilding the cell under the pointer would end its
// hover and undo the peek at once.
function windowIds(previous, windows) {
  var ids = [];
  for (var i = 0; i < windows.length; i++) ids.push(windows[i].id);
  if (ids.length === previous.length) {
    var same = true;
    for (var j = 0; j < ids.length; j++) if (ids[j] !== previous[j]) same = false;
    if (same) return previous;
  }
  return ids;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { initial: initial, transition: transition, liveItem: liveItem, windowIds: windowIds };
}
