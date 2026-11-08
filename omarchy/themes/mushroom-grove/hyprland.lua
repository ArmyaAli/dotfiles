local active_border_color = {
  colors = { "rgba(e86f5aff)", "rgba(e5b65dff)", "rgba(72b39eff)" },
  angle = 45,
}
local inactive_border_color = "rgba(69745d88)"

hl.config({
  general = {
    border_size = 2,
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    rounding = 10,
    rounding_power = 3,
    shadow = {
      enabled = true,
      range = 10,
      render_power = 3,
      color = "rgba(0b090888)",
      color_inactive = "rgba(0b090844)",
    },
  },
})
