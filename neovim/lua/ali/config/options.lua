vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

----------
-- SET --
----------

-- Keep pwd in sync with netrw
vim.g.netrw_keepdir = 0

-- Tab width - set to 2
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.softtabstop = 2

-- incremental search
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true

-- From lspconfig
-- Reserve a space in the gutter
-- This will avoid an annoying layout shift in the screen
vim.opt.signcolumn = 'yes'

-- Sensible modern UI defaults.
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.mouse = 'a'
vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath('state') .. '/undo'
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }
if vim.fn.has('nvim-0.12') == 1 then
  vim.opt.completeopt:append('popup')
end

-- Only force PowerShell when running on Windows.
if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
  vim.o.shell = "powershell.exe"
  vim.o.shellcmdflag = "-NoProfile -Command"
  vim.o.shellquote = ""
  vim.o.shellxquote = ""
end

----------
-- REMAP --
----------

-- Center cursor on moving down and up
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")


----------
-- Telescope --
----------

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
-- NOTE(Ali): requires ripgrep installed, or grep of choice needs to be configured
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telescope live grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
-- NOTE(Ali): I don't use this one too much
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })


----------
-- LSP --
----------

-- This is where you enable features that only work
-- if there is a language server active in the file
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local client = assert(vim.lsp.get_client_by_id(event.data.client_id))
    local opts = { buffer = event.buf }
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, vim.tbl_extend('force', opts, { desc = 'LSP hover' }))
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, vim.tbl_extend('force', opts, { desc = 'LSP definition' }))
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, vim.tbl_extend('force', opts, { desc = 'LSP declaration' }))
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, vim.tbl_extend('force', opts, { desc = 'LSP implementation' }))
    vim.keymap.set('n', 'go', vim.lsp.buf.type_definition, vim.tbl_extend('force', opts, { desc = 'LSP type definition' }))
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, vim.tbl_extend('force', opts, { desc = 'LSP references' }))
    vim.keymap.set('n', 'gs', vim.lsp.buf.signature_help, vim.tbl_extend('force', opts, { desc = 'LSP signature help' }))
    vim.keymap.set('n', '<F2>', vim.lsp.buf.rename, vim.tbl_extend('force', opts, { desc = 'LSP rename' }))
    -- Autoformat
    vim.keymap.set({ 'n', 'x' }, '<F3>', function() vim.lsp.buf.format({ async = true }) end, vim.tbl_extend('force', opts, { desc = 'Format buffer' }))
    vim.keymap.set('n', '<F4>', vim.lsp.buf.code_action, vim.tbl_extend('force', opts, { desc = 'LSP code action' }))

    -- Use Neovim's built-in LSP completion instead of a completion bridge.
    if client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
    end
  end,
})
