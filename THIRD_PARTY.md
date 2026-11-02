# Third-party source

| Component | Source | Pinned revision | License |
| --- | --- | --- | --- |
| StartBar 1.6.0 | [bmaltais/StartBar](https://github.com/bmaltais/StartBar) | `d94872b37610edd22db60ceeea6c8ff35c0525af` | [MIT](vendor/startbar/LICENSE) |
| Hyprbars | [hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins/tree/7644cecdb947060682891a0db2a0cdc5c0b9e704/hyprbars) | `7644cecdb947060682891a0db2a0cdc5c0b9e704` | [BSD-3-Clause](vendor/hyprbars/LICENSE) |

StartBar's local changes add active-window minimization and preserve restoration of minimized windows. Hyprbars' local changes add maximize-button hover commands, forwarding of native minimize requests, native Wayland maximize state synchronization, and raising floating windows on activation. Activating a maximized window also lowers other unpinned floating windows in its workspace. While loaded, it permits native maximize requests and reports the actual maximize state to Wayland clients. Unloading restores the previous suppression flag and advertised maximize state. StartBar's test pointer supports a persistent input stream for native double-click checks. Original copyright and license notices are retained.

Hyprbars also waits for four logical pixels of pointer movement before dragging and keeps the title bar under the pointer when restoring a maximized window for a drag. This avoids accidental drags during double-clicks and controls being placed above the screen.

The pinned compositor disables native XDG geometry cropping because it normally advertises maximized client state. Allowing native maximize/restore exposes GTK's transparent resize margins. Hyprbars hooks surface UV calculation, window hit testing, and surface bounds to keep the visible content, pointer coordinates, and pointer movement during a drag aligned. The hooks apply to mapped Wayland windows with nonzero, valid geometry offsets; popup selection and XWayland retain the original compositor behavior. Missing hook targets reject plugin loading, and unloading removes the hooks. The exact package and compositor locks remain required.

StartBar's window-recovery helper reads client and monitor snapshots through anonymous pipes instead of placing JSON in jq arguments. Local executable tests check that titles, initial titles, and monitor descriptions stay out of arguments while recovery still centers an off-screen window. Its optional event diagnostic now uses private runtime logs and passes paths as positional arguments to a static shell script. Four executable regressions cover permissions, quoting and runtime placement. The maintainer review and its limits are recorded in [SECURITY_REVIEW.md](SECURITY_REVIEW.md); independent security approval remains pending.

The bundle's own installer, helpers, palette, and Snap Layouts service are covered by the root [MIT license](LICENSE). Each vendored component keeps its own license.

[Fluent GTK](https://github.com/vinceliuice/Fluent-gtk-theme) is an optional separately installed theme. The installable bundle contains no Fluent source, standalone Microsoft wallpaper, Windows font, or Windows executable. The installer can copy the current wallpaper into the user's local theme directory; that copy stays outside this repository.

The documentation screenshots are real captures of a customized desktop with public demonstration content. They show locally installed applications, icons, and the user's selected wallpaper. Those pictured items are not installed from this repository.

Compatibility references: [Hyprland 0.56.2 window state handling](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/desktop/view/Window.cpp), [XDG minimize requests](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/protocols/XDGShell.cpp), and [Quickshell IPC](https://quickshell.org/docs/v0.2.1/types/Quickshell.Io/IpcHandler/).
