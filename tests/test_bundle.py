import copy
import importlib.util
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer", ROOT / "install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
window = runpy.run_path(str(ROOT / "bin/omarchy-to-windows-window"))


class ConfigurationTests(unittest.TestCase):
    def test_shell_preserves_custom_widgets_pins_and_plugin_settings(self):
        source = {
            "bar": {"layout": {"left": [{"id": "omarchy.menu"}, {"id": "example.hardware", "unit": "C"}],
                               "center": [{"id": "omarchy.clock"}], "right": [{"id": "omarchy.tray"}]},
                    "customValue": 7, "centerAnchor": "omarchy.clock"},
            "plugins": [{"id": installer.STARTBAR, "pins": ["example.browser"], "identityOverrides": {"test": "value"}},
                        {"id": "example.status", "custom": "keep"}],
            "disabledPlugins": ["example.disabled", installer.STARTBAR, installer.PLUGIN],
            "idle": {"enabled": False},
        }
        unchanged = copy.deepcopy(source)
        result = installer.shell_settings(source)
        self.assertEqual(source, unchanged)
        self.assertEqual(result["bar"]["layout"]["left"], [{"id": "example.hardware", "unit": "C"}])
        self.assertEqual(result["bar"]["layout"]["center"], [])
        self.assertEqual(result["bar"]["layout"]["right"], [{"id": "omarchy.tray"}])
        self.assertEqual(result["bar"]["customValue"], 7)
        startbar = next(entry for entry in result["plugins"] if entry["id"] == installer.STARTBAR)
        self.assertEqual(startbar["pins"], ["example.browser"])
        self.assertEqual(startbar["identityOverrides"], {"test": "value"})
        self.assertIn({"id": "example.status", "custom": "keep"}, result["plugins"])
        self.assertEqual(result["idle"], source["idle"])
        self.assertNotIn(installer.PLUGIN, result["disabledPlugins"])
        self.assertIn("example.disabled", result["disabledPlugins"])
        self.assertIn("omarchy.dock", result["disabledPlugins"])
        self.assertEqual(installer.shell_settings(result), result)

    def test_hyprland_module_replaces_only_legacy_require(self):
        source = 'require("hypr.monitors")\nrequire("hypr.windows-11")\nrequire("hypr.personal")\n'
        result = installer.hyprland_config(source)
        self.assertIn('require("hypr.personal")', result)
        self.assertIn('require("hypr.monitors")', result)
        self.assertNotIn('require("hypr.windows-11")', result)
        self.assertEqual(result.count('require("hypr.omarchy-to-windows")'), 1)
        self.assertEqual(installer.hyprland_config(result), result)

    def test_toml_and_ini_preserve_other_sections(self):
        original = '[font]\nbase-size = 11\nfamily = "Example Mono"\n\n[custom]\nvalue = true\n'
        result = installer.patch_section(original, "font", {"base-size": "14"})
        result = installer.patch_section(result, "bar", {"background": '"#202020"'})
        parsed = installer.tomllib.loads(result)
        self.assertEqual(parsed["font"], {"base-size": 14, "family": "Example Mono"})
        self.assertEqual(parsed["custom"], {"value": True})
        self.assertEqual(installer.patch_section(result, "font", {"base-size": "14"}), result)
        ini = installer.patch_section("[Settings]\nother=value\n", "Settings", {"gtk-font-name": "Inter 10"})
        self.assertIn("other=value", ini)

    def test_package_holds_preserve_repositories_and_other_holds(self):
        source = '[options]\nIgnorePkg = example-package\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n'
        result = installer.pacman_config(source, True)
        self.assertEqual(result.count(installer.INCLUDE), 1)
        self.assertLess(result.index(installer.INCLUDE), result.index("[core]"))
        self.assertIn("IgnorePkg = example-package", result)
        self.assertIn("Include = /etc/pacman.d/mirrorlist", result)
        self.assertEqual(installer.pacman_config(result, True), result)
        self.assertEqual(installer.pacman_config(result, False), source)
        with self.assertRaises(ValueError):
            installer.pacman_config("[core]\n", True)

    def test_snapshot_and_restore_files_directories_links_and_missing_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            installer.write(home / ".config/hypr/hyprland.lua", "original\n")
            installer.write(home / ".config/omarchy/plugins" / installer.STARTBAR / ".git/config", "local checkout\n")
            link = home / ".local/state/omarchy/current/background"
            link.parent.mkdir(parents=True)
            link.symlink_to("/missing-wallpaper")
            with patch.object(installer, "run", return_value="'original'"):
                installer.snapshot(home, root / "backup")
            installer.write(home / ".config/hypr/hyprland.lua", "modified\n")
            installer.write(home / ".local/bin/omarchy-to-windows-window", "new\n")
            installer.remove(home / ".config/omarchy/plugins" / installer.STARTBAR)
            link.unlink()
            installer.restore_snapshot(home, root / "backup", False)
            self.assertEqual((home / ".config/hypr/hyprland.lua").read_text(), "original\n")
            self.assertEqual((home / ".config/omarchy/plugins" / installer.STARTBAR / ".git/config").read_text(), "local checkout\n")
            self.assertFalse((home / ".local/bin/omarchy-to-windows-window").exists())
            self.assertEqual(os.readlink(link), "/missing-wallpaper")
            self.assertEqual((root / "backup").stat().st_mode & 0o777, 0o700)

    def test_restore_rejects_paths_outside_the_managed_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installer.write(root / "snapshot.json", json.dumps({"paths": {"../unrelated": True}}))
            with self.assertRaises(RuntimeError):
                installer.restore_snapshot(root / "home", root, False)

    def test_failed_snapshot_leaves_no_partial_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(installer, "run", side_effect=RuntimeError("settings unavailable")):
                with self.assertRaises(RuntimeError):
                    installer.snapshot(root / "home", root / "backup")
            self.assertEqual(list(root.iterdir()), [])

    def test_reload_preserves_restored_bar_visibility(self):
        with patch.object(installer, "run", side_effect=["ok", "[]"]) as command, patch.object(installer.subprocess, "run"):
            installer.reload_desktop()
        self.assertNotIn(unittest.mock.call(["omarchy-toggle-bar", "off"]), command.call_args_list)

    def test_existing_maximized_and_minimized_windows_become_floating(self):
        windows = [
            {"address": "0x1", "floating": False, "fullscreen": 1, "workspace": {"id": 1, "name": "1"}},
            {"address": "0x2", "floating": False, "fullscreen": 0, "workspace": {"id": -99, "name": "special:minimized"}},
            {"address": "0x3", "floating": False, "fullscreen": 0, "workspace": {"id": -98, "name": "special:personal"}},
        ]
        with patch.object(installer, "run", side_effect=[json.dumps(windows), "ok", "ok", "ok", "ok"]) as command:
            installer.float_existing_windows()
        operations = [call.args[0][-1] for call in command.call_args_list[1:]]
        self.assertIn('action="unset"', operations[0])
        self.assertIn('action="enable"', operations[1])
        self.assertIn('mode="maximized",action="set"', operations[2])
        self.assertIn('address:0x2', operations[3])
        self.assertTrue(all('address:0x3' not in operation for operation in operations))

    def test_activation_stops_if_plugin_loading_is_rejected(self):
        with patch.object(installer.subprocess, "run"), patch.object(installer, "unload"), \
                patch.object(installer, "run", return_value="ABI mismatch"), \
                patch.object(installer, "reload_desktop") as reload:
            with self.assertRaisesRegex(RuntimeError, "Hyprbars load failed: ABI mismatch"):
                installer.activate(Path("/example/home"))
        reload.assert_not_called()

    def test_stage_uses_frozen_plugin_copies_and_keeps_other_user_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, source = root / "home", root / "source"
            for relative in ("bin/omarchy-to-windows-window", "bin/omarchy-to-windows-desktop", "bin/omarchy-to-windows-theme",
                             "config/hyprland.lua", "config/native-titlebars", "config/fontconfig.conf",
                             "Service.qml", "manifest.json", "LICENSE", "theme/colors.toml", "theme/icons.theme"):
                installer.write(source / relative, (ROOT / relative).read_bytes())
            installer.write(source / "build/hyprbars.so", b"test binary fixture")
            installer.write(source / "vendor/startbar/manifest.json", '{"id":"' + installer.STARTBAR + '"}')
            installer.write(source / "vendor/startbar/.git/config", "must not install")
            installer.write(home / ".config/hypr/hyprland.lua", 'require("hypr.personal")\n')
            installer.write(home / ".config/omarchy/shell.json", json.dumps({"plugins": [{"id": installer.STARTBAR, "pins": ["example.editor"]}]}))
            installer.write(home / ".config/gtk-3.0/settings.ini", "[Settings]\ncustom=value\n")
            installer.write(home / ".config/gtk-4.0/gtk.css", "label { color: white; }\n")
            with patch.object(installer, "ROOT", source):
                installer.stage(home)
                first = (home / ".config/omarchy/shell.json").read_bytes()
                installer.stage(home)
            self.assertEqual((home / ".config/omarchy/shell.json").read_bytes(), first)
            self.assertFalse((home / ".config/omarchy/plugins" / installer.STARTBAR / ".git").exists())
            self.assertEqual((home / ".config/gtk-4.0/gtk.css").read_text(), "label { color: white; }\n")
            self.assertIn("custom=value", (home / ".config/gtk-3.0/settings.ini").read_text())
            self.assertIn("Adwaita-dark", (home / ".config/gtk-3.0/settings.ini").read_text())
            self.assertIn('require("hypr.personal")', (home / ".config/hypr/hyprland.lua").read_text())


class WindowTests(unittest.TestCase):
    def test_scaled_negative_origin_reserved_space_and_odd_width(self):
        monitor = dict(x=-1920, y=0, width=3840, height=2160, scale=2, reserved=[10, 30, 10, 48])
        self.assertEqual(window["geometry"](monitor, "right"), ([-959, 63], [948, 968]))
        monitor.update(x=0, width=1921, height=1080, scale=1, reserved=[0, 32, 0, 48])
        self.assertEqual(window["geometry"](monitor, "right", 0), ([961, 33], [959, 998]))
        self.assertEqual(window["geometry"](monitor, "zone", rect=[6, 6, 6, 6]), ([961, 565], [959, 466]))

    def test_native_titlebars_and_geometry_self_test(self):
        with tempfile.TemporaryDirectory() as directory:
            installer.write(Path(directory) / "omarchy-to-windows/native-titlebars", (ROOT / "config/native-titlebars").read_text())
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
                window["self_test"]()

    def test_invalid_addresses_and_rectangles_fail_before_dispatch(self):
        for args in (["minimize", "--window", "0x1;touch /tmp/unwanted"],
                     ["zone", "--rect", "0", "0", "0", "12"],
                     ["zone", "--rect", "-1", "0", "6", "12"],
                     ["zone", "--rect", "6", "0", "7", "12"], ["zone"]):
            with self.subTest(args=args):
                result = subprocess.run([sys.executable, str(ROOT / "bin/omarchy-to-windows-window"), *args],
                                        capture_output=True, text=True, env=os.environ | {"PATH": "/nonexistent"})
                self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
