local wezterm = require 'wezterm'
local config = {}

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

config.enable_tab_bar = false

return config
