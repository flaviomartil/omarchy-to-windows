# What StartBar does with data it does not control

A reviewer's checklist, from the marketplace reviews of 1.2.1 to 1.2.4 and a pass over the whole source. Each row is a place where text, files or processes from outside the plugin reach it, and what bounds it. `test/textFormat.test.js`, `test/plainText.test.js`, `test/dockIcons.test.js` and `test/dockHyprland.test.js` hold the checks that can be automated.

| Outside data | Where it goes | What bounds it |
| --- | --- | --- |
| The clipboard | Nothing reads it on its own. No native `TextInput` exists in the plugin (`PlainField.qml`). Ctrl+V runs `wl-paste` | `timeout 1`, `head -c 4096`, one line, control characters dropped, at most the field's `maxLength` (`PlainText.js`) |
| Window titles and classes (any app sets them) | Tooltips, Previews, Letter Tiles, App matching | Cut to 256 characters when read (`DockModel.clipText`); drawn as `Text.PlainText`, elided |
| Every other string drawn (App names, paths, settings) | `Text` items | All 49 are `Text.PlainText`, so no HTML or `<img>` is ever parsed, and a test fails on one that is not |
| Window addresses | Hyprland commands | Must be hex (`normalizedAddress`), passed to `bash` as an argument, never spliced into the script |
| Icon names (`Icon=` of a desktop entry) | `Quickshell.iconPath`, then a file search on a miss | Only `[A-Za-z0-9._+-]` names are searched for, as an argument; `find -type f` (no pipes or devices), `timeout 5`, 200 lines |
| Start menu search text | Filtering Apps | Plain `indexOf` (no regular expression), at most 256 characters |
| Places (your config) | `xdg-open` | An argv, never a shell; a path starting with `-` is made relative (`StartMenu.openCommand`) |
| `startCommand` and the Power rows | `bash -lc` | The command is yours (a setting) or fixed in `StartMenu.js`; nothing from a window or the clipboard is added to it |
| `shell.json`, `user-dirs.dirs`, `~/.face`, `startIcon` | Settings, Places, the avatar | Your own files. `JSON.parse` is wrapped in `try`; `~/.face` is checked with `test -f` first. They are read whole, as the shell reads its own config |

Not done: caret movement, selection and IME composition in the text fields, which a native `TextInput` would give but reads the clipboard to do.
