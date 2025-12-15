return {
  "shrynx/line-numbers.nvim",
  config = function()
    require("line-numbers").setup({
      mode = "both",
    })
  end,
}
