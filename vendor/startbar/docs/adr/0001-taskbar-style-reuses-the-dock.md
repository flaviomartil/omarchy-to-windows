> Superseded by [ADR 0002](0002-startbar-is-only-a-taskbar.md): the dock style was removed, so there is no `style` setting.

# Taskbar style is a second frame on the same Dock, not a second plugin

A Windows-11-like taskbar was requested after seeing another project's. We add it as a `style` setting (`dock` | `taskbar`) inside this plugin rather than forking or adding a plugin.

**Why:** the Items, Pins, Placed ordering, drag, menu, theming and the Hidden/Revealed auto-hide are the parts that work well and are shared unchanged. Only the frame differs (full-width bar, Start button, clock, pill indicator, hover previews).

**Consequences:**
- `dock` stays the default and its behaviour is untouched: always auto-hides, floats, reserves no space.
- The taskbar floats on the Top layer and reserves no space either; auto-hide is a setting (`autoHide`, off by default) that reuses the Dock's Reveal Strip and timers.
- The other project was studied from its README only; no code was read or copied (clean-room). The Start grid is drawn in QML.
