# StartBar is only a taskbar; the dock style is removed

Supersedes [ADR 0001](0001-taskbar-style-reuses-the-dock.md). The `style` setting (`dock` | `taskbar`) is gone and the plugin always draws the full-width bar with the Start button, clock, pill indicators, hover previews and Start menu.

**Why:** the plugin was renamed StartBar and is being published as a taskbar with a Start menu. A second, floating frame no longer fits that, and keeping it meant branching the frame geometry on the style (anchoring, spacing, icon sizing, indicators, menu placement) and carrying settings and rules that only the dock used (the dock always auto-hid, a separate right-click menu). With one frame all of that goes.

**Consequences:**
- Users on the old default (`dock`) get the taskbar after updating. Their Pins, Placed positions and other settings are kept.
- A leftover `style` key in a config entry, with either value, is ignored; nothing reads it and nothing rewrites it.
- Auto-hide remains as an option (`autoHide`, off by default) and reuses the Reveal Strip and the Hidden/Revealed rules.
- The Dock stays the domain term for the panel, and the file and identifier names (`DockModel.js`, `dockSettings`...) are unchanged.
