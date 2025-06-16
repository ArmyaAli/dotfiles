local wezterm = require 'wezterm'

local config = {}
if wezterm.config_builder then
  config = wezterm.config_builder()
end

local act = wezterm.action

config.color_scheme = 'Batman'
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
    { key = 's', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = 'v', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
    { key = 'h', action = act.ActivatePaneDirection 'Left' },
    { key = 'j', action = act.ActivatePaneDirection 'Down' },
    { key = 'k', action = act.ActivatePaneDirection 'Up' },
    { key = 'l', action = act.ActivatePaneDirection 'Right' },
  },
}

-- This is the main keybinding configuration.
config.keys = {
  {
    key = 'w',
    mods = 'CTRL',
    -- This is the crucial part.
    -- We check the name of the program running in the pane.
    -- The '~' means NOT. So, this keybinding is active only when the
    -- process name is NOT nvim (or vi, or vim).
    pane = {
      foreground_process_name = '~nvim|vim|vi',
    },
    -- When pressed, it activates our key table for 1 second.
    action = act.ActivateKeyTable { name = 'nvim_like_mode', timeout_milliseconds = 1000 },
  },
}

return config
