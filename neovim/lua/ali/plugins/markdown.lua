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
    ft = { "markdown" },
    build = "cd app && ./install.sh",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_refresh_slow = 0
    end,
    config = function()
      local function register_markdown_preview_commands(bufnr)
        vim.api.nvim_buf_create_user_command(bufnr, "MarkdownPreview", function()
          vim.fn["mkdp#util#open_preview_page"]()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "MarkdownPreviewStop", function()
          vim.fn["mkdp#util#stop_preview"]()
        end, {})

        vim.api.nvim_buf_create_user_command(bufnr, "MarkdownPreviewToggle", function()
          vim.fn["mkdp#util#toggle_preview"]()
        end, {})
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function(event)
          register_markdown_preview_commands(event.buf)
        end,
      })

      if vim.bo.filetype == "markdown" then
        register_markdown_preview_commands(0)
      end

      vim.keymap.set("n", "<leader>mm", "<cmd>MarkdownPreviewToggle<CR>", { desc = "Markdown Browser Preview" })
    end,
  },
}
