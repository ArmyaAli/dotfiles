return {
  -- Mason
  {
    "williamboman/mason.nvim",
    config = function()
      -- Mason to manage language servers
      require('mason').setup({})
    end
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = {
      "williamboman/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    config = function()
      local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
      local servers = {
        vtsls = {},
        clangd = {},
        pyright = {},
        lua_ls = {
          settings = {
            Lua = {
              runtime = {
                version = 'LuaJIT',
              },
              diagnostics = {
                globals = {
                  'vim',
                  'require'
                },
              },
              workspace = {
                library = vim.api.nvim_get_runtime_file("", true),
              },
              telemetry = {
                enable = false,
              },
            },
          },
        },
      }

      if is_windows then
        servers.powershell_es = {
          filetypes = { "ps1", "psm1", "psd1" },
          bundle_path = vim.fn.stdpath("data") .. "/mason/packages/powershell-editor-services",
          settings = { powershell = { codeFormatting = { Preset = 'OTBS' } } },
          init_options = {
            enableProfileLoading = false,
          },
        }
      end

      for server_name, server_config in pairs(servers) do
        vim.lsp.config(server_name, server_config)
      end

      -- Mason installs servers first, then enables the ones that are available.
      require('mason-lspconfig').setup({
        ensure_installed = vim.tbl_keys(servers),
        automatic_enable = true,
      })
    end,
  },
}
