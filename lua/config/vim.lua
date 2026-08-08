-- Leader keys first. `config.lazy` is required immediately after this module, and
-- plugin specs bind `<leader>` while being parsed -- if these are set later, those
-- mappings silently attach to the wrong key.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Disable netrw up front rather than after a file explorer plugin has already raced
-- it for the `BufEnter` on a directory.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local opt = vim.opt

opt.number = true
opt.relativenumber = true

-- Reserve the gutter permanently, so text does not jump sideways the moment a
-- diagnostic or git sign appears.
opt.signcolumn = "yes"

opt.termguicolors = true
opt.clipboard = "unnamedplus"

-- Persist undo history between sessions.
opt.undofile = true

opt.splitbelow = true
opt.splitright = true

opt.ignorecase = true
opt.smartcase = true

opt.scrolloff = 8

-- Indentation options are deliberately absent. Neovim's built-in EditorConfig
-- support is enabled by default and applies this repo's `.editorconfig` `[*.lua]`
-- rules (tabs, width 4) to Lua buffers on its own. Setting `expandtab` or
-- `shiftwidth` here would fight it. See `:help editorconfig`.
