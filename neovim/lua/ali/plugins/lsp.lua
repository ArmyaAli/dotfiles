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
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local lspconfig = require('lspconfig')
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
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

      require('mason-lspconfig').setup({
        ensure_installed = vim.tbl_keys(servers),
        handlers = {
          function(server_name)
            local server_config = vim.tbl_deep_extend('force', {
              capabilities = capabilities,
            }, servers[server_name] or {})
            lspconfig[server_name].setup(server_config)
          end,
        },
      })
    end,
  },
  { 'hrsh7th/cmp-nvim-lsp' },
  { 'hrsh7th/nvim-cmp' },
}
