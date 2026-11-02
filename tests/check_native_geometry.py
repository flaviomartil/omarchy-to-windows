import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


def main():
    dev = Path(os.environ["XDG_RUNTIME_DIR"]) / "startbar-dev"
    state = {key: shlex.split(value)[0] for key, value in
             (line.split("=", 1) for line in (dev / "state").read_text().splitlines())}
    assert state["NSIG"] != os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"), "Use an isolated desktop"
    assert state["NWD"] != os.environ.get("WAYLAND_DISPLAY"), "Never drive the main desktop"
    assert (int(state["NW"]), int(state["NH"])) == (1920, 1080)
    instance = next(item for item in json.loads(subprocess.check_output(["hyprctl", "instances", "-j"]))
                    if item["instance"] == state["NSIG"])
    entries = dict(entry.split(b"=", 1) for entry in Path(f'/proc/{instance["pid"]}/environ').read_bytes().split(b"\0") if b"=" in entry)
    env = os.environ | {key.decode(): value.decode() for key, value in entries.items()
                        if key in (b"HOME", b"PATH", b"DBUS_SESSION_BUS_ADDRESS", b"XDG_CONFIG_HOME", b"XDG_DATA_HOME", b"XDG_STATE_HOME", b"XDG_CACHE_HOME")}
    env |= {"HYPRLAND_INSTANCE_SIGNATURE": state["NSIG"], "WAYLAND_DISPLAY": state["NWD"], "GTK_A11Y": "none"}
    assert Path(env["HOME"]).resolve() == (dev / "nest/home").resolve()
    root = Path(__file__).resolve().parents[1]
    config = Path(env["XDG_CONFIG_HOME"]) / "omarchy-to-windows"
    config.mkdir(parents=True, exist_ok=True)
    (config / "native-titlebars").write_bytes((root / "config/native-titlebars").read_bytes())
    loaded = json.loads(subprocess.check_output(["hyprctl", "plugin", "list", "-j"], env=env))
    assert not any(plugin["name"] == "hyprbars" for plugin in loaded), "Use a test session without Hyprbars already loaded"
    plugin = str(root / "build/hyprbars.so")
    result = subprocess.check_output(["hyprctl", "plugin", "load", plugin], env=env, text=True)
    assert result.strip() == "ok", result
    try:
        source = 'dofile("/usr/share/omarchy/default/hypr/helpers.lua"); local load = hl.plugin.load; hl.plugin.load = function() end; dofile(' + json.dumps(str(root / "config/hyprland.lua")) + '); hl.plugin.load = load'
        result = subprocess.check_output(["hyprctl", "eval", source], env=env, text=True)
        assert result.strip() == "ok", result
        subprocess.run([sys.executable, __file__, "--app"], env=env, check=True)
    finally:
        subprocess.run(["hyprctl", "plugin", "unload", plugin], env=env, check=True)


def check_app():
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gio, GLib, Gtk

    dev = Path(os.environ["XDG_RUNTIME_DIR"]) / "startbar-dev"
    assert Path.home().resolve() == (dev / "nest/home").resolve()
    app = Adw.Application(application_id="org.gnome.OmarchyGeometryTest", flags=Gio.ApplicationFlags.NON_UNIQUE)
    errors = []
    clicks = []
    drags = []
    pointer = None

    def activate(app):
        window = Adw.ApplicationWindow(application=app, default_width=640, default_height=400)
        box = Gtk.Box()
        box.add_css_class("geometry-probe")
        window.set_content(box)
        provider = Gtk.CssProvider()
        provider.load_from_string(".geometry-probe { background: #ff0000; }")
        Gtk.StyleContext.add_provider_for_display(window.get_display(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
        gesture = Gtk.GestureClick()
        gesture.connect("pressed", lambda gesture, count, x, y: clicks.append((x, y)))
        box.add_controller(gesture)
        drag = Gtk.GestureDrag()
        drag.connect("drag-update", lambda gesture, x, y: drags.append((x, y)))
        box.add_controller(drag)
        gesture.group(drag)
        window.present()

        def sample():
            nonlocal pointer
            try:
                clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"]))
                client = next(item for item in clients if item["class"] == "org.gnome.OmarchyGeometryTest")
                x, y = client["at"]
                width, height = client["size"]
                assert all(offset > 0 for offset in window.get_surface_transform()), "Expected native GTK resize margins"
                for region, length in ((f"{x},{y + height // 2} {width}x1", width),
                                       (f"{x + width // 2},{y} 1x{height}", height)):
                    png = subprocess.check_output(["grim", "-g", region, "-"])
                    pixels = subprocess.check_output(["magick", "-", "-depth", "8", "RGB:-"], input=png)
                    painted = [i for i in range(length) if pixels[i * 3] > 240 and pixels[i * 3 + 1] < 10 and pixels[i * 3 + 2] < 10]
                    assert painted and min(painted) == 0 and max(painted) == length - 1, ("Native content does not fill its compositor bounds", painted[:15], length)
                pointer = subprocess.Popen([str(dev / "nest/bin/vptr"), "stream", "0", "0", "1920", "1080"],
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

                def send(verb, px, py):
                    pointer.stdin.write(f"{verb} {px} {py}\n")
                    pointer.stdin.flush()
                    assert pointer.stdout.readline().strip() == "ok"
                    return False

                send("press", x + 40, y + 100)
                GLib.timeout_add(100, lambda: send("move", x + 60, y + 120))
                GLib.timeout_add(250, lambda: send("release", x + 60, y + 120))
            except Exception as error:
                errors.append(error)
            GLib.timeout_add(800, finish)
            return False

        def finish():
            if not errors and not (clicks and abs(clicks[-1][0] - 40) <= 1 and abs(clicks[-1][1] - 100) <= 1):
                errors.append(AssertionError(("Native input coordinates do not match the visible window", clicks)))
            if not errors and not (drags and abs(drags[-1][0] - 20) <= 1 and abs(drags[-1][1] - 20) <= 1):
                errors.append(AssertionError(("Native drag coordinates do not match the visible window", drags)))
            if pointer:
                pointer.stdin.close()
                pointer.wait(timeout=5)
            window.close()
            return False

        GLib.timeout_add(1500, sample)

    app.connect("activate", activate)
    app.run([])
    assert not errors, errors
    print("PASS: GTK native content fills the compositor bounds; clicks and dragging match the visible content")


if __name__ == "__main__":
    if sys.argv[1:] == ["--app"]:
        check_app()
    else:
        main()
