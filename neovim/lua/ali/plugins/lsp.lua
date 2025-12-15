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
    config = function()
      -- Add cmp_nvim_lsp capabilities settings to lspconfig
      -- This should be executed before you configure any language server
      local lspconfig_defaults = require('lspconfig').util.default_config
      lspconfig_defaults.capabilities = vim.tbl_deep_extend(
        'force',
        lspconfig_defaults.capabilities,
        require('cmp_nvim_lsp').default_capabilities()
      )
      -- wireup with Lsp-zero default config
      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls',
          'clangd',
          'powershell_es',
          'vtsls',
          'gopls'
        },
        handlers = {
          vtsls = function()
            require('lspconfig').vtsls.setup({})
          end,
          gopls = function()
            require('lspconfig').gopls.setup({
               on_attach = on_attach,
                capabilities = capabilities,
                cmd = {"gopls"},
                filetypes = { "go", "gomod", "gowork", "gotmpl" },
                settings = {
                  gopls = {
                    completeUnimported = true,
                    usePlaceholders = true,
                    analyses = {
                      unusedparams = true,
                    },
                  },
                },
            })
          end,
          clangd = function()
            require('lspconfig').clangd.setup({})
          end,
          lua_ls = function()
            require('lspconfig').lua_ls.setup {
              settings = {
                Lua = {
                  runtime = {
                    -- Tell the language server which version of Lua you're using
                    -- (most likely LuaJIT in the case of Neovim)
                    version = 'LuaJIT',
                  },
                  diagnostics = {
                    -- Get the language server to recognize the `vim` global
                    globals = {
                      'vim',
                      'require'
                    },
                  },
                  workspace = {
                    -- Make the server aware of Neovim runtime files
                    library = vim.api.nvim_get_runtime_file("", true),
                  },
                  -- Do not send telemetry data containing a randomized but unique identifier
                  telemetry = {
                    enable = false,
                  },
                },
              },
            }
          end,
          function ()
            powershell_es = require('lspconfig').powershell_es.setup({
              filetypes = {"ps1", "psm1", "psd1"},
              bundle_path = "~/AppData/Local/nvim-data/mason/packages/powershell-editor-services",
              settings = { powershell = { codeFormatting = { Preset = 'OTBS' } } },
              init_options = {
                enableProfileLoading = false,
              },
            })
          end
          },
        })
      end,
    },
    { 'neovim/nvim-lspconfig' },
  { 'hrsh7th/cmp-nvim-lsp' },
  { 'hrsh7th/nvim-cmp' },
}
