#define WLR_USE_UNSTABLE

#include <unistd.h>

#include <any>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleEffectContainer.hpp>
#include <hyprland/src/config/lua/bindings/LuaBindingsInternal.hpp>
#include <hyprland/src/config/lua/types/LuaConfigColor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/ElementRenderer.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/view/Popup.hpp>

#include <hyprutils/string/VarList.hpp>

#include <algorithm>

#include "barDeco.hpp"
#include "globals.hpp"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static CFunctionHook* nativeGeometryHook = nullptr;
static CFunctionHook* nativeInputHook = nullptr;
static CFunctionHook* nativeBoxHook = nullptr;
using UVFunction = void (*)(Render::IElementRenderer*, PHLWINDOW, SP<CWLSurfaceResource>, PHLMONITOR, bool, const Vector2D&, const Vector2D&, bool);
using InputFunction = SP<CWLSurfaceResource> (*)(const Desktop::CViewHitTester*, const Vector2D&, PHLWINDOW, Vector2D&);
using BoxFunction = std::optional<CBox> (*)(const Desktop::View::CWLSurface*);

static std::optional<CBox> nativeGeometry(PHLWINDOW window) {
    if (!window || window->m_isX11 || !window->m_xdgSurface || !window->m_isMapped)
        return std::nullopt;
    const auto geometry = window->m_xdgSurface->m_current.geometry;
    const auto size = window->wlSurface()->resource()->m_current.size;
    if (geometry.pos() == Vector2D{} || geometry.x < 0 || geometry.y < 0 || geometry.w <= 0 || geometry.h <= 0 || size.x <= 0 || size.y <= 0 ||
        geometry.x + geometry.w > size.x || geometry.y + geometry.h > size.y)
        return std::nullopt;
    return geometry;
}

static void calculateNativeUV(Render::IElementRenderer* renderer, PHLWINDOW window, SP<CWLSurfaceResource> surface, PHLMONITOR monitor, bool main,
                              const Vector2D& projected, const Vector2D& unscaled, bool misaligned) {
    reinterpret_cast<UVFunction>(nativeGeometryHook->m_original)(renderer, window, surface, monitor, main, projected, unscaled, misaligned);
    if (!main || !window || window->wlSurface()->resource() != surface)
        return;
    const auto geometry = nativeGeometry(window);
    const auto size = surface->m_current.size;
    if (!geometry)
        return;

    Vector2D topLeft, bottomRight{1, 1};
    if (surface->m_current.viewport.hasSource) {
        const auto buffer = surface->m_current.bufferSize;
        if (buffer.x <= 0 || buffer.y <= 0)
            return;
        const auto source = surface->m_current.viewport.source;
        topLeft = source.pos() / buffer;
        bottomRight = (source.pos() + source.size()) / buffer;
    }
    const auto span = bottomRight - topLeft;
    g_pHyprRenderer->m_renderData.primarySurfaceUVTopLeft = topLeft + geometry->pos() / size * span;
    g_pHyprRenderer->m_renderData.primarySurfaceUVBottomRight = topLeft + (geometry->pos() + geometry->size()) / size * span;
}

static SP<CWLSurfaceResource> nativeSurfaceAt(const Desktop::CViewHitTester* tester, const Vector2D& pos, PHLWINDOW window, Vector2D& local) {
    const auto found = reinterpret_cast<InputFunction>(nativeInputHook->m_original)(tester, pos, window, local);
    const auto geometry = nativeGeometry(window);
    if (!geometry || (window->m_popupHead && window->m_popupHead->at(pos)))
        return found;
    auto [surface, coordinates] = window->wlSurface()->resource()->at(pos - window->position(Desktop::View::IGeometric::GEOMETRIC_GOAL) + geometry->pos(), true);
    local = coordinates;
    return surface;
}

static std::optional<CBox> nativeSurfaceBox(const Desktop::View::CWLSurface* surface) {
    auto box = reinterpret_cast<BoxFunction>(nativeBoxHook->m_original)(surface);
    const auto window = Desktop::View::CWindow::fromView(surface->view());
    const auto geometry = nativeGeometry(window);
    if (box && geometry) {
        box->translate(-geometry->pos());
        box->w = window->wlSurface()->resource()->m_current.size.x;
        box->h = window->wlSurface()->resource()->m_current.size.y;
    }
    return box;
}

static void onNewWindow(PHLWINDOW window) {
    if (!window->m_X11DoesntWantBorders) {
        if (std::ranges::any_of(window->m_windowDecorations, [](const auto& d) { return d->getDisplayName() == "Hyprbar"; }))
            return;

        auto bar = makeUnique<CHyprBar>(window);
        g_pGlobalState->bars.emplace_back(bar);
        bar->m_self = bar;
        HyprlandAPI::addWindowDecoration(PHANDLE, window, std::move(bar));
    }
}

static void onPreConfigReload() {
    g_pGlobalState->buttons.clear();
}

static void onWindowActive(PHLWINDOW window, Desktop::eFocusReason) {
    if (!window || !window->m_isMapped || !window->m_isFloating)
        return;

    if (Fullscreen::controller()->isFullscreen(window)) {
        const auto windows = Desktop::windowState()->windows();
        for (auto it = windows.rbegin(); it != windows.rend(); ++it) {
            const auto& other = *it;
            if (other != window && other->m_isMapped && other->m_isFloating && !other->m_pinned && other->m_workspace == window->m_workspace)
                Desktop::windowState()->lower(other);
        }
    }
    Desktop::windowState()->raise(window);
}

static void onConfigReloaded() {
    for (auto& b : g_pGlobalState->bars) {
        if (!b)
            continue;

        b->onConfigReloaded();
    }
}

static void onUpdateWindowRules(PHLWINDOW window) {
    const auto BARIT = std::find_if(g_pGlobalState->bars.begin(), g_pGlobalState->bars.end(), [window](const auto& bar) { return bar->getOwner() == window; });

    if (BARIT == g_pGlobalState->bars.end())
        return;

    (*BARIT)->updateRules();
    window->updateWindowDecos();
}

Hyprlang::CParseResult onNewButton(const char* K, const char* V) {
    std::string                 v = V;
    Hyprutils::String::CVarList vars(v);

    Hyprlang::CParseResult      result;

    // hyprbars-button = bgcolor, size, icon, action, fgcolor

    if (vars[0].empty() || vars[1].empty()) {
        result.setError("bgcolor and size cannot be empty");
        return result;
    }

    float size = 10;
    try {
        size = std::stof(vars[1]);
    } catch (std::exception& e) {
        result.setError("failed to parse size");
        return result;
    }

    bool userfg  = false;
    auto fgcolor = Config::ParserUtils::parseColor("rgb(ffffff)");
    auto bgcolor = Config::ParserUtils::parseColor(vars[0]);

    if (!bgcolor) {
        result.setError("invalid bgcolor");
        return result;
    }

    if (vars.size() == 5) {
        userfg  = true;
        fgcolor = Config::ParserUtils::parseColor(vars[4]);
    }

    if (!fgcolor) {
        result.setError("invalid fgcolor");
        return result;
    }

    g_pGlobalState->buttons.push_back(SHyprButton{vars[3], userfg, *fgcolor, *bgcolor, size, vars[2]});

    for (auto& b : g_pGlobalState->bars) {
        b->m_bButtonsDirty = true;
    }

    return result;
}

int newLuaButton(lua_State* L) {
    if (!lua_istable(L, 1))
        return Config::Lua::Bindings::Internal::configError(L, "add_button: expected a table { bg_color, fg_color, size, icon, action }");

    SHyprButton button;

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "bg_color");

        Config::Lua::CLuaConfigColor parser(0);
        auto                         err = parser.parse(L);
        if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
            return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse bg_color");

        button.bgcol = parser.parsed();
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "fg_color");

        Config::Lua::CLuaConfigColor parser(0);
        auto                         err = parser.parse(L);
        if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
            return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse fg_color");

        button.userfg = true;
        button.fgcol = parser.parsed();
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "size");

        if (!lua_isnumber(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: size must be an integer");

        button.size = lua_tointeger(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "icon");

        if (!lua_isstring(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: icon must be a string");

        button.icon = lua_tostring(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "action");

        if (!lua_isstring(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: action must be a string");

        button.cmd = lua_tostring(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });
        lua_getfield(L, 1, "hover_action");
        if (!lua_isnil(L, -1)) {
            if (!lua_isstring(L, -1))
                return Config::Lua::Bindings::Internal::configError(L, "add_button: hover_action must be a string");
            button.hoverCmd = lua_tostring(L, -1);
        }
    }

    g_pGlobalState->buttons.push_back(std::move(button));

    for (auto& b : g_pGlobalState->bars) {
        b->m_bButtonsDirty = true;
    }

    return 0;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[hyprbars] Failure in initialization: Version mismatch (headers ver is not equal to running hyprland ver)",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[hb] Version mismatch");
    }

    const auto hook = [&](const std::string& name, const std::string& prefix, const void* destination) {
        const auto functions = HyprlandAPI::findFunctionsByName(PHANDLE, name);
        const auto match = std::ranges::find_if(functions, [&](const auto& function) { return function.demangled.starts_with(prefix); });
        if (match == functions.end())
            throw std::runtime_error("[hb] Native window geometry function is unavailable: " + name);
        auto result = HyprlandAPI::createFunctionHook(PHANDLE, match->address, destination);
        if (!result || !result->hook())
            throw std::runtime_error("[hb] Native window geometry hook failed: " + name);
        return result;
    };
    nativeGeometryHook = hook("calculateUVForSurface", "Render::IElementRenderer::calculateUVForSurface(", reinterpret_cast<void*>(&calculateNativeUV));
    nativeInputHook = hook("windowSurfaceAt", "Desktop::CViewHitTester::windowSurfaceAt(", reinterpret_cast<void*>(&nativeSurfaceAt));
    nativeBoxHook = hook("getSurfaceBoxGlobal", "Desktop::View::CWLSurface::getSurfaceBoxGlobal(", reinterpret_cast<void*>(&nativeSurfaceBox));

    g_pGlobalState                    = makeUnique<SGlobalState>();
    g_pGlobalState->nobarRuleIdx      = Desktop::Rule::windowEffects()->registerEffect("hyprbars:no_bar");
    g_pGlobalState->barColorRuleIdx   = Desktop::Rule::windowEffects()->registerEffect("hyprbars:bar_color");
    g_pGlobalState->titleColorRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:title_color");

    static auto P  = Event::bus()->m_events.window.open.listen([&](PHLWINDOW w) { onNewWindow(w); });
    static auto P2 = Event::bus()->m_events.window.active.listen([](PHLWINDOW w, Desktop::eFocusReason reason) { onWindowActive(w, reason); });
    static auto P3 = Event::bus()->m_events.window.updateRules.listen([&](PHLWINDOW w) { onUpdateWindowRules(w); });

    g_pGlobalState->config.barColor            = makeShared<Config::Values::CColorValue>("plugin:hyprbars:bar_color", "Change the bar color", 0x88333333);
    g_pGlobalState->config.textColor           = makeShared<Config::Values::CColorValue>("plugin:hyprbars:col.text", "Change the text color", 0xffffffff);
    g_pGlobalState->config.inactiveButtonColor = makeShared<Config::Values::CColorValue>(
        "plugin:hyprbars:inactive_button_color", "Change the inactive button's color. 0x00000000 means unset", 0x00000000);
    g_pGlobalState->config.barHeight       = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_height", "Change the bar's height", 15);
    g_pGlobalState->config.barTextSize     = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_text_size", "Change the bar's text size", 10);
    g_pGlobalState->config.barTextWeight   = makeShared<Config::Values::CFontWeightValue>("plugin:hyprbars:bar_text_weight", "Bar's title text weight (e.g. \"bold\" or an integer 100-1000)", 400);
    g_pGlobalState->config.barTitleEnabled = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_title_enabled", "Whether to enable titles in the bar", true);
    g_pGlobalState->config.barBlur         = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_blur", "Whether to enable blur of the bar", false);
    g_pGlobalState->config.barTextFont     = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_font", "Bar's text font", "Sans");
    g_pGlobalState->config.barTextAlign    = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_align", "Bar's text alignment", "center");
    g_pGlobalState->config.barPartOfWindow =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_part_of_window", "Whether the bar is a part of the window (reserves space)", true);
    g_pGlobalState->config.barPrecedenceOverBorder =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_precedence_over_border", "Whether the bar is before, or after the border", false);
    g_pGlobalState->config.barButtonsAlignment = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_buttons_alignment", "Alignment of the bar buttons", "right");
    g_pGlobalState->config.barPadding          = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_padding", "Padding of the bar", 7);
    g_pGlobalState->config.barButtonPadding    = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_button_padding", "Padding of the bar buttons", 5);
    g_pGlobalState->config.enabled             = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:enabled", "Whether bars are enabled", true);
    g_pGlobalState->config.iconOnHover         = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:icon_on_hover", "Whether to use an icon on hover of the buttons", false);
    g_pGlobalState->config.onDoubleClick       = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_double_click", "Action to execute on double click of the bar", "");

    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.textColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.inactiveButtonColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barHeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextSize);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextWeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTitleEnabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barBlur);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextFont);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextAlign);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPartOfWindow);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPrecedenceOverBorder);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barButtonsAlignment);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPadding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barButtonPadding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.enabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.iconOnHover);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onDoubleClick);

    if (Config::mgr()->type() == Config::CONFIG_LEGACY)
        HyprlandAPI::addConfigKeyword(PHANDLE, "plugin:hyprbars:hyprbars-button", onNewButton, Hyprlang::SHandlerOptions{});
    else
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "add_button", ::newLuaButton);
    static auto P4 = Event::bus()->m_events.config.preReload.listen([&] { onPreConfigReload(); });
    static auto P5 = Event::bus()->m_events.config.reloaded.listen([&] { onConfigReloaded(); });

    // add deco to existing windows
    for (auto& w : Desktop::windowState()->windows()) {
        if (w->isHidden() || !w->m_isMapped)
            continue;

        onNewWindow(w);
    }

    HyprlandAPI::reloadConfig();

    return {"hyprbars", "A plugin to add title bars to windows.", "Vaxry", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    for (auto hook : {nativeGeometryHook, nativeInputHook, nativeBoxHook})
        if (hook)
            HyprlandAPI::removeFunctionHook(PHANDLE, hook);
    nativeGeometryHook = nativeInputHook = nativeBoxHook = nullptr;

    for (auto& m : State::monitorState()->monitors())
        m->m_scheduledRecalc = true;

    g_pHyprRenderer->m_renderPass.removeAllOfType("CBarPassElement");

    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->barColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->titleColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->nobarRuleIdx);
}
