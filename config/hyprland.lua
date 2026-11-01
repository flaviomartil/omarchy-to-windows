local home = os.getenv("HOME")
local config = os.getenv("XDG_CONFIG_HOME") or home .. "/.config"

hl.config({
  input = { follow_mouse = 0, float_switch_override_focus = 0 },
  general = {
    gaps_in = 0,
    gaps_out = 0,
    border_size = 1,
    resize_on_border = true,
    snap = { enabled = true, window_gap = 10, monitor_gap = 10 },
  },
  decoration = {
    rounding = 8,
    active_opacity = 1,
    inactive_opacity = 1,
    shadow = { enabled = true, range = 20, render_power = 3, color = "rgba(00000030)" },
    blur = { enabled = true, size = 4, passes = 2 },
  },
})

o.window(".*", { float = true, opacity = "1 override 1 override" })
o.window({ tag = "chromium-based-browser" }, { float = true })
hl.plugin.load(home .. "/.local/lib/omarchy/hyprbars-omarchy-to-windows.so")

if hl.plugin.hyprbars then
  hl.config({
    plugin = {
      hyprbars = {
        bar_height = 32,
        bar_color = "rgb(202020)",
        ["col.text"] = "rgb(f3f3f3)",
        bar_text_font = "Inter",
        bar_text_size = 13,
        bar_text_align = "left",
        bar_buttons_alignment = "right",
        bar_padding = 12,
        bar_button_padding = 14,
        bar_part_of_window = true,
        on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
      },
    },
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(202020)", fg_color = "rgb(f3f3f3)", size = 22,
    icon = "×", action = "hyprctl dispatch 'hl.dsp.window.close()'",
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(202020)", fg_color = "rgb(f3f3f3)", size = 22,
    icon = "□", action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })'",
    hover_action = "omarchy-shell io.github.flaviomartil.omarchy-to-windows",
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(202020)", fg_color = "rgb(f3f3f3)", size = 22,
    icon = "−", action = "omarchy-to-windows-window minimize",
  })
  local file = assert(io.open(config .. "/omarchy-to-windows/native-titlebars", "r"))
  local native = file:read("*a"):match("^%s*(.-)%s*$")
  file:close()
  hl.window_rule({ match = { class = native }, ["hyprbars:no_bar"] = true })
end

local bindings = {
  { "SUPER + SUPER_L", "Start menu", "omarchy-shell io.github.bmaltais.startbar startMenu", { release = true } },
  { "SUPER + E", "File Explorer", { omarchy = "nautilus" } },
  { "SUPER + D", "Show desktop", "omarchy-to-windows-desktop" },
  { "SUPER + LEFT", "Snap left", "omarchy-to-windows-window left" },
  { "SUPER + RIGHT", "Snap right", "omarchy-to-windows-window right" },
  { "SUPER + UP", "Maximize window", "omarchy-to-windows-window maximize" },
  { "SUPER + DOWN", "Restore or minimize window", "omarchy-to-windows-window down" },
  { "SUPER + M", "Minimize window", "omarchy-to-windows-window minimize" },
  { "SUPER + Z", "Snap layouts", "omarchy-shell io.github.flaviomartil.omarchy-to-windows open" },
  { "SUPER + SHIFT + LEFT", "Focus left", hl.dsp.focus({ direction = "l" }) },
  { "SUPER + SHIFT + RIGHT", "Focus right", hl.dsp.focus({ direction = "r" }) },
  { "SUPER + SHIFT + UP", "Focus up", hl.dsp.focus({ direction = "u" }) },
  { "SUPER + SHIFT + DOWN", "Focus down", hl.dsp.focus({ direction = "d" }) },
  { "ALT + F4", "Close window", hl.dsp.window.close() },
  { "SUPER + A", "Status bar", "omarchy-toggle-bar" },
  { "SUPER + L", "Lock session", "omarchy-system-lock" },
  { "CTRL + ALT + DELETE", "Session menu", "omarchy-menu toggle system" },
  { "CTRL + SHIFT + ESCAPE", "Task Manager", { tui = "btop" } },
}
hl.unbind("SUPER + SHIFT + T")
for _, binding in ipairs(bindings) do
  hl.unbind(binding[1])
  o.bind(binding[1], binding[2], binding[3], binding[4])
end

local optional = {
  { "expose.window-overview", "SUPER + TAB", "Task view", hl.dsp.event("expose.window-overview:toggle") },
  { "jankeesvw.notification-center", "SUPER + N", "Notification Center", "omarchy-shell jankeesvw.notification-center" },
}
for _, binding in ipairs(optional) do
  local file = io.open(config .. "/omarchy/plugins/" .. binding[1] .. "/manifest.json", "r")
  if file then
    file:close()
    hl.unbind(binding[2])
    o.bind(binding[2], binding[3], binding[4])
  end
end
