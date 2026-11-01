#!/usr/bin/env python3
import argparse
import configparser
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parent
LOCK = json.loads((ROOT / "versions.lock.json").read_text())
PLUGIN = "io.github.flaviomartil.omarchy-to-windows"
STARTBAR = "io.github.bmaltais.startbar"
INCLUDE = "Include = /etc/pacman.d/omarchy-to-windows.conf"
PIN_FILE = Path("/etc/pacman.d/omarchy-to-windows.conf")
PIN_CONTENT = "IgnorePkg = " + " ".join(LOCK["packages"]) + "\n"
GSETTINGS = {
    "org.gnome.desktop.interface": ["color-scheme", "gtk-theme", "font-name"],
    "org.gnome.desktop.wm.preferences": ["button-layout"],
}
MANAGED = [
    ".config/hypr/hyprland.lua",
    ".config/hypr/omarchy-to-windows.lua",
    ".config/omarchy-to-windows",
    ".config/omarchy/shell.json",
    ".config/omarchy/shell.toml",
    ".config/omarchy/plugins/" + PLUGIN,
    ".config/omarchy/plugins/" + STARTBAR,
    ".config/omarchy/themes/omarchy-to-windows",
    ".config/omarchy/hooks/theme-set.d/omarchy-to-windows",
    ".config/fontconfig/conf.d/99-omarchy-to-windows-shell.conf",
    ".config/gtk-3.0/settings.ini",
    ".config/gtk-4.0/settings.ini",
    ".config/gtk-4.0/gtk.css",
    ".local/bin/omarchy-to-windows-window",
    ".local/bin/omarchy-to-windows-desktop",
    ".local/lib/omarchy/hyprbars-omarchy-to-windows.so",
    ".local/state/omarchy/current",
    ".local/state/omarchy/toggles/bar-off",
]


def run(argv, **kwargs):
    return subprocess.check_output(argv, text=True, **kwargs).strip()


def write(path, content, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".omarchy-to-windows-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content.encode() if isinstance(content, str) else content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def remove(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def copy_path(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(os.readlink(source))
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)


def patch_section(text, section, updates):
    lines = text.splitlines()
    header = "[" + section + "]"
    start = next((i for i, line in enumerate(lines) if line.strip() == header), None)
    if start is None:
        lines.extend(([""] if lines else []) + [header])
        start = len(lines) - 1
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
    pending = dict(updates)
    for i in range(start + 1, end):
        match = re.match(r"\s*([\w-]+)\s*=", lines[i])
        if match and match[1] in pending:
            key = match[1]
            lines[i] = key + " = " + pending.pop(key)
    lines[end:end] = [key + " = " + value for key, value in pending.items()]
    return "\n".join(lines) + "\n"


def shell_settings(original):
    settings = copy.deepcopy(original)
    bar = settings.setdefault("bar", {})
    bar.update(position="top", transparent=False)
    duplicates = {"omarchy.menu", "omarchy.clock", "omarchy.power", "omarchy.workspaces",
                  "omarchy.active-window", "omarchy.dock", STARTBAR}
    layout = bar.setdefault("layout", {})
    for position in ("left", "center", "right"):
        layout[position] = [entry for entry in layout.get(position, []) if entry.get("id") not in duplicates]
    if bar.get("centerAnchor") in duplicates:
        bar.pop("centerAnchor")
    plugins = settings.setdefault("plugins", [])
    for identifier in (STARTBAR, PLUGIN):
        if not any(entry.get("id") == identifier for entry in plugins):
            plugins.append({"id": identifier})
    startbar = next(entry for entry in plugins if entry.get("id") == STARTBAR)
    startbar.update(position="bottom", reserveSpace=True, alignment="center", showClock=True,
                    colorScheme="dark", barHeight=48, iconSize=32, groupWindows=True,
                    showWorkspaceBadge=False, autoHide=False, transparent=False, opacity=0.94,
                    showStart=True, startIcon="grid", startPlaces=[], newWindowWorkspace="off",
                    hideOmarchyDock=True)
    disabled = settings.setdefault("disabledPlugins", [])
    settings["disabledPlugins"] = [identifier for identifier in disabled if identifier not in (PLUGIN, STARTBAR)]
    for identifier in ("omarchy.dock", "martil.snap-layouts"):
        if identifier not in settings["disabledPlugins"]:
            settings["disabledPlugins"].append(identifier)
    return settings


def hyprland_config(text):
    text = re.sub(r'^\s*require\(([\'"])hypr\.windows-11\1\)\s*$', "", text, flags=re.MULTILINE)
    require = 'require("hypr.omarchy-to-windows")'
    if not re.search(r'require\(([\'"])hypr\.omarchy-to-windows\1\)', text):
        text = text.rstrip() + "\n\n" + require + "\n"
    return text


def pacman_config(text, enable):
    lines = [line for line in text.splitlines() if line.strip() != INCLUDE]
    if enable:
        options = next((i for i, line in enumerate(lines) if line.strip() == "[options]"), None)
        if options is None:
            raise ValueError("pacman.conf has no [options] section")
        lines.insert(options + 1, INCLUDE)
    return "\n".join(lines) + "\n"


def pins(enable):
    if os.geteuid() != 0:
        raise RuntimeError("run pin/unpin with sudo")
    path = Path("/etc/pacman.conf")
    before = path.read_text()
    old_pin = PIN_FILE.read_text() if PIN_FILE.exists() else None
    if old_pin not in (None, PIN_CONTENT):
        raise RuntimeError("the managed package hold file was changed; inspect it before continuing")
    after = pacman_config(before, enable)
    changed = after != before or (old_pin is None and enable)
    try:
        if enable:
            write(PIN_FILE, PIN_CONTENT, 0o644)
        write(path, after, path.stat().st_mode & 0o777)
        effective = run(["pacman-conf", "IgnorePkg"]).split()
        if enable and not set(LOCK["packages"]).issubset(effective):
            raise RuntimeError("pacman did not read all package holds")
        if not enable:
            PIN_FILE.unlink(missing_ok=True)
    except Exception:
        write(path, before, path.stat().st_mode & 0o777)
        if old_pin is None:
            PIN_FILE.unlink(missing_ok=True)
        else:
            write(PIN_FILE, old_pin, 0o644)
        raise
    print(("Held" if enable else "Released") + " " + str(len(LOCK["packages"])) + " desktop packages")
    return changed


def verify_versions():
    installed = dict(line.split(maxsplit=1) for line in run(["pacman", "-Q", *LOCK["packages"]]).splitlines())
    mismatches = [name + ": expected " + version + ", found " + installed.get(name, "missing")
                  for name, version in LOCK["packages"].items() if installed.get(name) != version]
    if mismatches:
        raise RuntimeError("unsupported desktop package versions:\n" + "\n".join(mismatches))
    version = json.loads(run(["hyprctl", "version", "-j"]))
    if version.get("commit") != LOCK["hyprlandCommit"]:
        raise RuntimeError("the running Hyprland does not match versions.lock.json; restart into the pinned build")


def snapshot(home, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix="snapshot-", dir=destination.parent))
    try:
        paths = {}
        for relative in MANAGED:
            source = home / relative
            paths[relative] = source.exists() or source.is_symlink()
            if paths[relative]:
                copy_path(source, temporary / "files" / relative)
        values = {schema: {key: run(["gsettings", "get", schema, key]) for key in keys}
                  for schema, keys in GSETTINGS.items()}
        metadata = {"paths": paths, "gsettings": values, "pinnedByInstaller": False}
        write(temporary / "snapshot.json", json.dumps(metadata, indent=2) + "\n")
        temporary.rename(destination)
        return metadata
    finally:
        if temporary.exists():
            remove(temporary)


def restore_snapshot(home, source, activate):
    metadata = json.loads((source / "snapshot.json").read_text())
    if set(metadata["paths"]) != set(MANAGED):
        raise RuntimeError("backup manifest does not match this installer")
    for relative, existed in metadata["paths"].items():
        destination = home / relative
        remove(destination)
        if existed:
            copy_path(source / "files" / relative, destination)
    if activate:
        for schema, values in metadata["gsettings"].items():
            for key, value in values.items():
                run(["gsettings", "set", schema, key, value])


def stage(home):
    config = home / ".config"
    for filename in ("omarchy-to-windows-window", "omarchy-to-windows-desktop"):
        write(home / ".local/bin" / filename, (ROOT / "bin" / filename).read_bytes(), 0o755)
    write(home / ".local/lib/omarchy/hyprbars-omarchy-to-windows.so", (ROOT / "build/hyprbars.so").read_bytes(), 0o755)
    write(config / "hypr/omarchy-to-windows.lua", (ROOT / "config/hyprland.lua").read_text())
    write(config / "omarchy-to-windows/native-titlebars", (ROOT / "config/native-titlebars").read_text())
    write(config / "fontconfig/conf.d/99-omarchy-to-windows-shell.conf", (ROOT / "config/fontconfig.conf").read_text())
    write(config / "omarchy/hooks/theme-set.d/omarchy-to-windows", (ROOT / "bin/omarchy-to-windows-theme").read_bytes(), 0o755)
    plugin = config / "omarchy/plugins" / PLUGIN
    remove(plugin)
    for filename in ("Service.qml", "manifest.json", "LICENSE"):
        write(plugin / filename, (ROOT / filename).read_bytes())
    startbar = config / "omarchy/plugins" / STARTBAR
    remove(startbar)
    shutil.copytree(ROOT / "vendor/startbar", startbar,
                    ignore=shutil.ignore_patterns(".git", "node_modules", "__pycache__", "*.log"))
    shell = config / "omarchy/shell.json"
    settings = json.loads(shell.read_text()) if shell.exists() else {}
    write(shell, json.dumps(shell_settings(settings), indent=2) + "\n")
    shell_toml = config / "omarchy/shell.toml"
    content = shell_toml.read_text() if shell_toml.exists() else ""
    content = patch_section(content, "font", {"base-size": "14"})
    content = patch_section(content, "bar", {"background": '"#202020"', "background-alpha": "0.98",
                                           "text": '"#f3f3f3"', "scale-with-font": "false", "size-horizontal": "32"})
    tomllib.loads(content)
    write(shell_toml, content)
    theme = config / "omarchy/themes/omarchy-to-windows"
    theme.mkdir(parents=True, exist_ok=True)
    for filename in ("colors.toml", "icons.theme"):
        write(theme / filename, (ROOT / "theme" / filename).read_bytes())
    background = home / ".local/state/omarchy/current/background"
    if background.is_file() and not any((theme / "backgrounds").glob("*")):
        destination = theme / "backgrounds" / ("local-wallpaper" + background.resolve().suffix)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(background, destination)
    fluent = home / ".local/share/themes/Fluent-Windows-11"
    gtk_theme = "Fluent-Windows-11" if fluent.is_dir() else "Adwaita-dark"
    for version in ("3.0", "4.0"):
        ini = config / ("gtk-" + version) / "settings.ini"
        content = ini.read_text() if ini.exists() else ""
        content = patch_section(content, "Settings", {
            "gtk-theme-name": gtk_theme, "gtk-font-name": "Inter 10",
            "gtk-application-prefer-dark-theme": "true", "gtk-decoration-layout": ":minimize,maximize,close",
        })
        parser = configparser.ConfigParser()
        parser.read_string(content)
        write(ini, content)
    css = fluent / "gtk-4.0/gtk-dark.css"
    if css.is_file():
        target = config / "gtk-4.0/gtk.css"
        content = target.read_text() if target.exists() else ""
        statement = "@import url(" + json.dumps(css.as_uri()) + ");"
        if statement not in content:
            write(target, statement + "\n" + content)
    main = config / "hypr/hyprland.lua"
    write(main, hyprland_config(main.read_text()))


def unload(home):
    loaded = json.loads(run(["hyprctl", "plugin", "list", "-j"]))
    if any(plugin.get("name") == "hyprbars" for plugin in loaded):
        for name in ("hyprbars-omarchy-to-windows.so", "hyprbars-windows-11-0.56.2.so", "hyprbars-0.56.2.so"):
            subprocess.run(["hyprctl", "plugin", "unload", str(home / ".local/lib/omarchy" / name)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reload_desktop(show_bar=False):
    run(["hyprctl", "reload"])
    errors = [message for message in json.loads(run(["hyprctl", "configerrors", "-j"])) if message]
    if errors:
        raise RuntimeError("Hyprland rejected the configuration:\n" + "\n".join(errors))
    if show_bar:
        run(["omarchy-toggle-bar", "off"])
    subprocess.run(["omarchy-restart-shell"], check=True, timeout=120)


def activate(home):
    env = os.environ | {"OMARCHY_THEME_HEADLESS": "1"}
    subprocess.run(["omarchy-theme-set", "omarchy-to-windows"], env=env, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["bash", str(home / ".config/omarchy/hooks/theme-set.d/omarchy-to-windows"), "omarchy-to-windows"], check=True)
    unload(home)
    loaded = run(["hyprctl", "plugin", "load", str(home / ".local/lib/omarchy/hyprbars-omarchy-to-windows.so")])
    if loaded != "ok":
        raise RuntimeError("Hyprbars load failed: " + loaded)
    reload_desktop(show_bar=True)
    float_existing_windows()
    subprocess.run(["omarchy-theme-set-foot"], check=True)


def float_existing_windows():
    for window in json.loads(run(["hyprctl", "clients", "-j"])):
        workspace = window["workspace"]
        if not window["floating"] and (workspace["id"] > 0 or workspace["name"] == "special:minimized"):
            address = window["address"]
            if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
                raise RuntimeError("invalid address from Hyprland")
            target = 'window="address:' + address + '"'
            mode = "maximized" if window["fullscreen"] == 1 else "fullscreen"
            commands = ['hl.dsp.window.float({action="enable",' + target + '})']
            if window["fullscreen"]:
                commands.insert(0, 'hl.dsp.window.fullscreen({mode="' + mode + '",action="unset",' + target + '})')
                commands.append('hl.dsp.window.fullscreen({mode="' + mode + '",action="set",' + target + '})')
            for command in commands:
                result = run(["hyprctl", "dispatch", command])
                if result != "ok":
                    raise RuntimeError(result)


def doctor(home):
    verify_versions()
    errors = [message for message in json.loads(run(["hyprctl", "configerrors", "-j"])) if message]
    if errors:
        raise RuntimeError("Hyprland configuration errors: " + "; ".join(errors))
    plugins = json.loads(run(["hyprctl", "plugin", "list", "-j"]))
    if not any(plugin.get("name") == "hyprbars" for plugin in plugins):
        raise RuntimeError("Hyprbars is not loaded")
    for identifier in (PLUGIN, STARTBAR):
        path = home / ".config/omarchy/plugins" / identifier
        if (path / ".git").exists():
            raise RuntimeError(identifier + " is still managed by the plugin updater")
    run([str(home / ".local/bin/omarchy-to-windows-window"), "self-test"])
    state = json.loads(run(["omarchy-shell", PLUGIN, "state"]))
    if not isinstance(state, dict):
        raise RuntimeError("Snap Layouts service is unavailable")
    settings = json.loads((home / ".config/omarchy/shell.json").read_text())
    if any(identifier in settings.get("disabledPlugins", []) for identifier in (PLUGIN, STARTBAR)):
        raise RuntimeError("a required shell service is disabled")
    held = set(run(["pacman-conf", "IgnorePkg"]).split())
    print("PASS: package versions, Hyprland, frozen plugins, Snap Layouts, and 11 geometry checks")
    print("Package holds: " + str(len(set(LOCK["packages"]) & held)) + "/" + str(len(LOCK["packages"])))


def install(home, activate_now, pin_packages):
    verify_versions()
    if not (home / ".config/hypr/hyprland.lua").is_file():
        raise RuntimeError("an existing Omarchy Hyprland configuration is required")
    (ROOT / "build").mkdir(exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="hyprbars-", suffix=".so", dir=ROOT / "build")
    os.close(fd)
    try:
        subprocess.run(["make", "-B", "-C", str(ROOT / "vendor/hyprbars"), "TARGET=" + temporary], check=True)
        os.replace(temporary, ROOT / "build/hyprbars.so")
    finally:
        Path(temporary).unlink(missing_ok=True)
    state = home / ".local/state/omarchy-to-windows"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    baseline = state / "backup"
    if not baseline.exists():
        snapshot(home, baseline)
    attempt = Path(tempfile.mkdtemp(prefix="attempt-", dir=state))
    attempt.rmdir()
    snapshot(home, attempt)
    pinned_here = False
    try:
        stage(home)
        if pin_packages:
            was_held = PIN_FILE.exists() and PIN_FILE.read_text() == PIN_CONTENT and INCLUDE in Path("/etc/pacman.conf").read_text().splitlines()
            subprocess.run(["sudo", sys.executable, str(ROOT / "install.py"), "pin"], check=True)
            pinned_here = not was_held
        if activate_now:
            activate(home)
            doctor(home)
        metadata = json.loads((baseline / "snapshot.json").read_text())
        metadata["pinnedByInstaller"] |= pinned_here
        write(baseline / "snapshot.json", json.dumps(metadata, indent=2) + "\n")
    except Exception:
        if activate_now:
            unload(home)
        restore_snapshot(home, attempt, activate_now)
        if pinned_here:
            subprocess.run(["sudo", sys.executable, str(ROOT / "install.py"), "unpin"], check=True)
        if activate_now:
            reload_desktop()
        raise
    finally:
        remove(attempt)
    print("Installed Omarchy to Windows. Private backup: " + str(baseline))


def main():
    parser = argparse.ArgumentParser(description="Install the pinned Omarchy to Windows desktop bundle")
    parser.add_argument("command", choices=["install", "restore", "doctor", "pin", "unpin"])
    parser.add_argument("--pin-packages", action="store_true", help="hold the desktop packages in pacman (requires sudo)")
    parser.add_argument("--no-activate", action="store_true", help="skip explicit desktop reload and GNOME appearance changes")
    args = parser.parse_args()
    os.umask(0o077)
    if args.command in ("pin", "unpin"):
        pins(args.command == "pin")
        return
    if os.geteuid() == 0:
        parser.error("run user installation commands as your desktop user")
    home = Path.home()
    expected = {"XDG_CONFIG_HOME": home / ".config", "XDG_DATA_HOME": home / ".local/share", "XDG_STATE_HOME": home / ".local/state"}
    if any(os.environ.get(key) and Path(os.environ[key]) != value for key, value in expected.items()):
        parser.error("custom XDG directories are not supported by this Omarchy bundle")
    if args.command == "install":
        install(home, not args.no_activate, args.pin_packages)
    elif args.command == "doctor":
        doctor(home)
    else:
        baseline = home / ".local/state/omarchy-to-windows/backup"
        metadata = json.loads((baseline / "snapshot.json").read_text())
        if not args.no_activate:
            unload(home)
        restore_snapshot(home, baseline, not args.no_activate)
        if metadata["pinnedByInstaller"]:
            subprocess.run(["sudo", sys.executable, str(ROOT / "install.py"), "unpin"], check=True)
        if not args.no_activate:
            reload_desktop()
        print("Restored the configuration saved before installation")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("Error: " + str(error), file=sys.stderr)
        sys.exit(1)
