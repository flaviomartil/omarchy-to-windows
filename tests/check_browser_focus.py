import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def wait_for(check):
    for _ in range(150):
        result = check()
        if result:
            return result
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for the isolated desktop")


def main():
    dev = Path(os.environ["XDG_RUNTIME_DIR"]) / "startbar-dev"
    state = {}
    for line in (dev / "state").read_text().splitlines():
        key, _, value = line.partition("=")
        state[key] = shlex.split(value)[0]
    assert state["NSIG"] != os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"), "Use an isolated test session"
    assert state["NWD"] != os.environ.get("WAYLAND_DISPLAY"), "Never drive the main desktop"
    assert (int(state["NW"]), int(state["NH"])) == (1920, 1080)
    instance = next(item for item in json.loads(subprocess.check_output(
        ["hyprctl", "instances", "-j"], text=True)) if item["instance"] == state["NSIG"])
    session_env = dict(entry.split(b"=", 1) for entry in Path("/proc/" + str(instance["pid"]) + "/environ").read_bytes().split(b"\0") if b"=" in entry)
    env = os.environ | {key.decode(): value.decode() for key, value in session_env.items()
                        if key in (b"HOME", b"PATH", b"DBUS_SESSION_BUS_ADDRESS", b"XDG_CONFIG_HOME", b"XDG_DATA_HOME", b"XDG_STATE_HOME", b"XDG_CACHE_HOME")}
    env |= {"HYPRLAND_INSTANCE_SIGNATURE": state["NSIG"], "WAYLAND_DISPLAY": state["NWD"]}
    config = Path(env.get("XDG_CONFIG_HOME", str(Path(env["HOME"]) / ".config")))
    assert config.resolve() != Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))).resolve()
    (config / "omarchy-to-windows").mkdir(parents=True, exist_ok=True)
    (config / "omarchy-to-windows/native-titlebars").write_bytes((ROOT / "config/native-titlebars").read_bytes())
    env["GSETTINGS_BACKEND"] = "keyfile"
    subprocess.run(["gsettings", "set", "org.gnome.desktop.wm.preferences", "button-layout", ":minimize,maximize,close"], env=env, check=True)
    plugin = str(ROOT / "build/hyprbars.so")
    omarchy = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
    source = "\n".join([
        "dofile(" + json.dumps(str(omarchy / "default/hypr/helpers.lua")) + ")",
        'o.window(".*", { suppress_event = "maximize" })',
        "dofile(" + json.dumps(str(omarchy / "default/hypr/apps/browser.lua")) + ")",
        "local load = hl.plugin.load",
        "hl.plugin.load = function() end",
        "dofile(" + json.dumps(str(ROOT / "config/hyprland.lua")) + ")",
        "hl.plugin.load = load",
    ])
    subprocess.run(["hyprctl", "reload"], env=env, check=True)
    result = subprocess.check_output(["hyprctl", "plugin", "load", plugin], env=env, text=True)
    assert result.strip() == "ok", result
    subprocess.run(["hyprctl", "eval", source], env=env, check=True)

    def query(name):
        return json.loads(subprocess.check_output(["hyprctl", name, "-j"], env=env, text=True))

    def dispatch(expression):
        result = subprocess.check_output(["hyprctl", "dispatch", expression], env=env, text=True)
        assert result.strip() == "ok", result

    def window(app_class):
        return next((item for item in query("clients") if item["class"] == app_class), None)

    subprocess.run(["hyprctl", "eval", "hl.config({ input = { resolve_binds_by_sym = true } })"], env=env, check=True)

    def start_menu():
        return json.loads(subprocess.check_output([
            "omarchy-shell", "io.github.bmaltais.startbar", "layout",
        ], env=env, text=True))["menus"]["start"]

    def check_start_keys():
        subprocess.run(["omarchy-shell", "io.github.bmaltais.startbar", "closeStartMenu"], env=env, check=True)
        for key in ("Super_L", "Super_R"):
            subprocess.run(["wtype", "-k", key], env=env, check=True)
            time.sleep(0.8)
            assert start_menu() is not None, key + " alone did not open Start"
            subprocess.run(["wtype", "-k", key], env=env, check=True)
            time.sleep(0.8)
            assert start_menu() is None, key + " did not close Start"
            subprocess.run(["wtype", "-P", key, "-k", "z", "-p", key], env=env, check=True)
            time.sleep(0.8)
            assert start_menu() is None, key + "+Z opened Start"
        print("PASS: both Super keys toggle Start alone and leave shortcuts alone", flush=True)

    assert window("chromium") is None and window("omarchy-focus-terminal") is None
    assert not any(query("configerrors")), query("configerrors")
    assert len(query("monitors")) == 1, "Use one 1920x1080 output in the isolated session"
    processes = []
    pointer = subprocess.Popen([str(dev / "nest/bin/vptr"), "stream", "0", "0", "1920", "1080"],
                               env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, start_new_session=True)
    processes.append(pointer)
    with tempfile.TemporaryDirectory(prefix="omarchy-browser-focus-") as directory:
        temporary = Path(directory)
        with (temporary / "apps.log").open("w") as output:
            try:
                check_start_keys()
                page = temporary / "browser.html"
                page.write_text('<!doctype html><title>Browser focus regression</title><style>html,body{background:#204080;margin:0;height:100%}</style>')
                processes.append(subprocess.Popen([
                    "chromium", "--ozone-platform=wayland", "--disable-gpu", "--no-first-run",
                    "--no-default-browser-check", "--disable-background-networking", "--disable-sync",
                    "--disable-extensions", "--password-store=basic",
                    "--user-data-dir=" + str(temporary / "chromium"), page.as_uri(),
                ], env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True))
                browser_window = wait_for(lambda: window("chromium"))
                browser_address = browser_window["address"]
                if browser_window["floating"]:
                    dispatch('hl.dsp.window.resize({ x = 1200, y = 800, relative = false, window = "address:' + browser_address + '" })')
                    dispatch('hl.dsp.window.move({ x = 100, y = 100, relative = false, window = "address:' + browser_address + '" })')
                processes.append(subprocess.Popen([
                    "foot", "-c", "/dev/null", "--app-id=omarchy-focus-terminal", "-o", "colors-dark.background=a02020", "sleep", "120",
                ], env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True))
                terminal_address = wait_for(lambda: window("omarchy-focus-terminal"))["address"]
                dispatch('hl.dsp.window.resize({ x = 900, y = 600, relative = false, window = "address:' + terminal_address + '" })')
                dispatch('hl.dsp.window.move({ x = 700, y = 250, relative = false, window = "address:' + terminal_address + '" })')
                dispatch('hl.dsp.focus({ window = "address:' + terminal_address + '" })')

                def point(action, x, y, pause=0.3):
                    pointer.stdin.write(f"{action} {x} {y}\n")
                    pointer.stdin.flush()
                    assert pointer.stdout.readline().strip() == "ok", "Virtual pointer failed"
                    time.sleep(pause)

                def click_taskbar(address):
                    layout = json.loads(subprocess.check_output([
                        "omarchy-shell", "io.github.bmaltais.startbar", "layout",
                    ], env=env, text=True))
                    item = next(item for item in layout["items"] if item["key"] == "window:" + address.removeprefix("0x"))
                    point("click", round(item["x"] + item["width"] / 2),
                          round(item["y"] + item["height"] / 2), 0.8)

                def overlap_pixel(x=1000, y=500):
                    image = temporary / "overlap.png"
                    subprocess.run(["grim", "-o", state["NMON"], str(image)], env=env, check=True)
                    pixel = subprocess.check_output([
                        "magick", str(image), "-format",
                        f"%[fx:p{{{x},{y}}}.r*255] %[fx:p{{{x},{y}}}.g*255] %[fx:p{{{x},{y}}}.b*255]", "info:",
                    ], text=True)
                    return tuple(map(float, pixel.split()))

                time.sleep(1)
                for app_class in ("chromium", "omarchy-focus-terminal"):
                    current = window(app_class)
                    print(app_class, {key: current[key] for key in ("floating", "at", "size", "workspace", "monitor")}, flush=True)
                pixel = overlap_pixel()
                assert pixel[0] > pixel[2] + 40, ("Terminal did not cover the browser before the click", pixel)
                point("move", 200, 300)
                assert query("activewindow")["address"] == terminal_address, "Hover changed keyboard focus"
                point("click", 200, 300)
                wait_for(lambda: query("activewindow").get("address") == browser_address)
                pixel = overlap_pixel()
                print("Browser floating:", window("chromium")["floating"], "overlap pixel:", pixel, flush=True)
                assert pixel[2] > pixel[0] + 40, "Browser received focus, but the terminal remained above it"
                assert window("chromium")["floating"], "A newly opened Chromium window remained tiled"
                point("click", 1500, 700)
                wait_for(lambda: query("activewindow").get("address") == terminal_address)
                pixel = overlap_pixel()
                assert pixel[0] > pixel[2] + 40, "Clicking the terminal did not raise it"
                print("PASS: new Chromium window floats; hover preserves focus; clicks raise browser and terminal", flush=True)

                click_taskbar(terminal_address)
                wait_for(lambda: window("omarchy-focus-terminal")["workspace"]["name"] == "special:minimized")
                click_taskbar(terminal_address)
                wait_for(lambda: query("activewindow").get("address") == terminal_address)
                assert window("omarchy-focus-terminal")["workspace"]["id"] == 1
                click_taskbar(browser_address)
                wait_for(lambda: query("activewindow").get("address") == browser_address)
                pixel = overlap_pixel()
                assert pixel[2] > pixel[0] + 40, "Taskbar did not raise the browser"
                print("PASS: taskbar minimizes, restores and raises overlapping windows", flush=True)

                dispatch('hl.dsp.focus({ window = "address:' + browser_address + '" })')
                dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + browser_address + '" })')
                time.sleep(0.3)
                original = window("chromium")

                def native_maximize(action):
                    current = window("chromium")
                    offset = 48 if current["fullscreen"] else 38
                    x = current["at"][0] + (current["size"][0] - offset if action == "button" else 600)
                    y = current["at"][1] + (24 if current["fullscreen"] else 30)
                    point("move", x, y, 0.05)
                    point("click", x, y, 0.05)
                    if action == "double-click":
                        point("click", x, y, 0.05)
                    time.sleep(0.5)

                for action in ("double-click", "button"):
                    native_maximize(action)
                    current = window("chromium")
                    if current["fullscreen"] != 1:
                        subprocess.run(["grim", "-o", state["NMON"], str(dev / "maximize-failure.png")], env=env, check=True)
                    assert current["fullscreen"] == 1, (action + " did not maximize Chromium", current["size"])
                    pixel = overlap_pixel(1800, 900)
                    assert pixel[2] > pixel[0] + 40, ("Maximized browser did not cover the desktop", pixel)
                    pixel = overlap_pixel()
                    assert pixel[2] > pixel[0] + 40, ("Terminal remained above the maximized browser", pixel)
                    native_maximize(action)
                    current = window("chromium")
                    if current["fullscreen"] or current["size"] != original["size"]:
                        subprocess.run(["grim", "-o", state["NMON"], str(dev / "maximize-failure.png")], env=env, check=True)
                        print("Restore failure focus:", query("activewindow").get("class"), "cursor:", query("cursorpos"), flush=True)
                    assert current["fullscreen"] == 0 and current["size"] == original["size"], (action + " did not restore Chromium", current["fullscreen"], current["at"], current["size"], original["size"])

                native_maximize("double-click")
                assert window("chromium")["fullscreen"] == 1
                click_taskbar(terminal_address)
                time.sleep(0.3)
                assert query("activewindow")["address"] == terminal_address, "Activation did not focus the terminal"
                pixel = overlap_pixel()
                assert pixel[0] > pixel[2] + 40, ("Focused terminal remained behind the maximized browser", pixel)
                click_taskbar(browser_address)
                assert query("activewindow")["address"] == browser_address
                pixel = overlap_pixel()
                assert pixel[2] > pixel[0] + 40, ("Clicking the browser did not raise it again", pixel)
                native_maximize("double-click")
                assert window("chromium")["fullscreen"] == 0
                print("PASS: activating the terminal raises it above a maximized browser; clicking the browser raises it again", flush=True)

                dispatch('hl.dsp.focus({ window = "address:' + terminal_address + '" })')
                time.sleep(0.3)
                terminal_original = window("omarchy-focus-terminal")

                def terminal_maximize(action):
                    current = window("omarchy-focus-terminal")
                    x = current["at"][0] + (current["size"][0] - 73 if action == "button" else 200)
                    y = current["at"][1] - 16
                    point("move", x, y, 0.05)
                    point("click", x, y, 0.05)
                    if action == "double-click":
                        point("click", x, y, 0.05)
                    time.sleep(0.5)

                for action in ("double-click", "button"):
                    terminal_maximize(action)
                    current = window("omarchy-focus-terminal")
                    assert current["fullscreen"] == 1, (action + " did not maximize the terminal", current["at"], current["size"])
                    assert current["at"][1] >= 32, ("Terminal title bar moved above the screen", current["at"])
                    terminal_maximize("button")
                    current = window("omarchy-focus-terminal")
                    assert current["fullscreen"] == 0 and current["at"] == terminal_original["at"] and current["size"] == terminal_original["size"], ("Terminal maximize control did not restore its window", current["at"], current["size"])

                terminal_maximize("double-click")
                current = window("omarchy-focus-terminal")
                x, y = current["at"][0] + 600, current["at"][1] - 16
                point("press", x, y, 0.05)
                point("move", x + 10, y + 5, 0.05)
                point("move", x + 20, y + 10, 0.05)
                point("release", x + 20, y + 10)
                current = window("omarchy-focus-terminal")
                assert current["fullscreen"] == 0 and current["at"][1] >= 32, ("Dragging a maximized terminal hid its controls above the screen", current["at"], current["size"])
                assert current["at"][1] - 32 <= y + 10 <= current["at"][1], ("Restored terminal title bar did not stay under the pointer", current["at"], y + 10)
                dispatch('hl.dsp.window.move({ x = 700, y = 250, relative = false, window = "address:' + terminal_address + '" })')

                time.sleep(0.5)
                x, y = terminal_original["at"][0] + 200, terminal_original["at"][1] - 16
                point("press", x, y, 0.05)
                point("move", x + 1, y + 1, 0.05)
                point("move", x + 2, y + 2, 0.05)
                point("release", x + 2, y + 2)
                point("move", 1000, 700)
                current = window("omarchy-focus-terminal")
                assert current["at"] == terminal_original["at"] and current["size"] == terminal_original["size"], ("A small title-bar click movement dragged the terminal", current["at"], current["size"])
                time.sleep(0.5)
                point("press", x, y, 0.05)
                point("move", x + 2, y + 2, 0.05)
                point("release", x + 2, y + 2, 0.05)
                point("click", x + 2, y + 2)
                assert window("omarchy-focus-terminal")["fullscreen"] == 1, "Small pointer movement prevented terminal double-click maximize"
                terminal_maximize("button")

                current = window("omarchy-focus-terminal")
                point("click", current["at"][0] + current["size"][0] - 109, current["at"][1] - 16)
                wait_for(lambda: window("omarchy-focus-terminal")["workspace"]["name"] == "special:minimized")
                dispatch('hl.dsp.window.move({ workspace = "1", follow = false, window = "address:' + terminal_address + '" })')
                print("PASS: terminal double-click, click movement, maximize/restore, minimize, and dragging from maximized keep controls accessible", flush=True)

                dispatch('hl.dsp.focus({ window = "address:' + browser_address + '" })')
                time.sleep(0.3)
                subprocess.run(["hyprctl", "plugin", "unload", plugin], env=env, check=True)
                native_maximize("double-click")
                assert window("chromium")["fullscreen"] == 0, "Unloading the plugin did not restore stock maximize suppression"
                subprocess.run(["hyprctl", "plugin", "load", plugin], env=env, check=True)
                subprocess.run(["hyprctl", "eval", source], env=env, check=True)
                native_maximize("double-click")
                assert window("chromium")["fullscreen"] == 1, "Loading the plugin did not enable maximize for an existing window"
                native_maximize("double-click")
                assert window("chromium")["fullscreen"] == 0
                print("PASS: native maximize button and double-click maximize/restore; unloading restores stock behavior; reloading repairs existing windows", flush=True)

                dispatch('hl.dsp.focus({ window = "address:' + terminal_address + '" })')
                time.sleep(0.3)
                current = window("omarchy-focus-terminal")
                point("click", current["at"][0] + current["size"][0] - 37, current["at"][1] - 16)
                wait_for(lambda: window("omarchy-focus-terminal") is None)
                print("PASS: terminal close button closes only the disposable terminal", flush=True)
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait(timeout=5)
                subprocess.run(["hyprctl", "plugin", "unload", plugin], env=env, check=True)


if __name__ == "__main__":
    main()
