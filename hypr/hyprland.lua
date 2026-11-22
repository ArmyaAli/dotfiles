-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Watching a fullscreen video should not blank, lock, or suspend the session.
-- Stremio never takes a Wayland idle inhibitor of its own (mpv and browsers
-- do), so the omarchy idle service would still lock mid-playback. Holding the
-- inhibitor only while its window is fullscreen keeps idle behavior intact
-- when Stremio sits paused or backgrounded.
o.window("com.stremio.Stremio", { idle_inhibit = "fullscreen" })

-- Flatpak apps (Stremio, installed after this session started) only show up in
-- the Omarchy launcher when its exports directory is on XDG_DATA_DIRS.
-- /etc/profile.d/flatpak.sh does this for login shells, which the session may
-- not have run; keep the two in sync without duplicating the path.
do
  local exports = "/var/lib/flatpak/exports/share"
  local data_dirs = os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"

  if not (":" .. data_dirs .. ":"):find(":" .. exports .. ":", 1, true) then
    hl.env("XDG_DATA_DIRS", exports .. ":" .. data_dirs)
  end
end

-- Hyprland 0.56.2 aborts in CWorkspace::updateWindows() whenever a window's
-- floating state changes while its workspace is in the scrolling layout
-- (upstream hyprwm/Hyprland#16121). That makes the workspace-layout cycle
-- (SUPER + L) crash on a scrolling workspace, and a raw float toggle there too.
--
-- The cycle is routed through dwindle, which changes floating state while
-- scrolling is off the workspace; direct float toggles are refused instead of
-- taking the compositor down. Remove these guards once Hyprland ships a fix.
-- Wrapped once per Lua state: a reload may re-run this file on top of the
-- wrapper it installed last time, and a second layer would detour twice.
if not o.workspace_mode_guarded then
  local workspace_mode_unguarded = o.workspace_mode

  local function workspace_floats(workspace)
    for _, window in ipairs(hl.get_windows({ tag = "omarchy-floating-workspace" })) do
      if window.workspace and tostring(window.workspace.id) == tostring(workspace) then
        return true
      end
    end

    return false
  end

  function o.workspace_mode(spec)
    spec = spec or {}

    local active = hl.get_active_workspace()
    local scrolling = active
      and active.tiled_layout == "scrolling"
      and spec.workspace ~= nil
      and tostring(active.id) == tostring(spec.workspace)

    if scrolling and (spec.mode == "floating" or workspace_floats(spec.workspace)) then
      workspace_mode_unguarded({ workspace = tostring(spec.workspace), mode = "dwindle" })

      if spec.mode == "dwindle" then
        return
      end
    end

    return workspace_mode_unguarded(spec)
  end

  o.workspace_mode_guarded = true
end

local function refuse_floating_on_scrolling()
  local active = hl.get_active_workspace()

  if not active or active.tiled_layout ~= "scrolling" then
    return false
  end

  hl.exec_cmd("omarchy-notification-send -u normal -g 󰘖 'Floating needs a tiling layout' 'Hyprland 0.56.2 crashes when a scrolling workspace floats a window. Cycle the workspace layout with SUPER + L first.'")

  return true
end

o.rebind("SUPER + T", "Toggle window floating/tiling", function()
  if not refuse_floating_on_scrolling() then
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  end
end)

o.rebind("SUPER + O", "Pop window out (float & pin)", function()
  if not refuse_floating_on_scrolling() then
    hl.exec_cmd("omarchy-hyprland-window-pop")
  end
end)
