return {
  {
    "ellisonleao/glow.nvim",
    cmd = "Glow",
    config = function()
      require("glow").setup({
        style = "dark",
        width = 120,
      })

      vim.keymap.set("n", "<leader>mg", "<cmd>Glow<CR>", { desc = "Markdown Glow Preview" })
    end,
  },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_refresh_slow = 0
    end,
    config = function()
      vim.keymap.set("n", "<leader>mm", "<cmd>MarkdownPreviewToggle<CR>", { desc = "Markdown Browser Preview" })
    end,
  },
}