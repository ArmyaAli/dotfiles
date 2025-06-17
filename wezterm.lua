local wezterm = require 'wezterm'

local config = {}

local act = wezterm.action

config.automatically_reload_config = true
config.color_scheme = 'Gruvbox dark, hard (base16)'
config.default_prog = { 'powershell' }
config.default_cwd = "C:\\dev"
config.window_close_confirmation = 'AlwaysPrompt'

config.window_padding = {
  right = '0cell',
  top = '0.1cell',
  bottom = '0cell'
}

-- This table defines the keys that will be active *after* you press Ctrl-w.
-- It's like Neovim's window command mode.
config.key_tables = {
  nvim_like_mode = {
    { key = 'v', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = 's', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
    { key = 'h', action = act.ActivatePaneDirection 'Left' },
    { key = 'j', action = act.ActivatePaneDirection 'Down' },
    { key = 'k', action = act.ActivatePaneDirection 'Up' },
    { key = 'l', action = act.ActivatePaneDirection 'Right' },
  },
}

config.keys = {
  {
    key = 'w',
    mods = 'SHIFT',
    action = wezterm.action_callback(function(window, pane)
        window:perform_action( act.ActivateKeyTable { name = 'nvim_like_mode', timeout_milliseconds = 1000 },
          pane
        )
    end),
  },
}

return config
