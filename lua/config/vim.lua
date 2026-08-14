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
--
-- Two columns rather than one, because both kinds of sign want the same cell and only
-- the higher priority would be drawn. mini.diff's hunk extmarks sit at priority 199
-- (`lua/plugin/diff.lua`); `vim.diagnostic` signs use a base of 10. At `yes` the hunk
-- mark would hide every error and warning sign in the file. The cost is one permanent
-- column of width.
opt.signcolumn = "yes:2"

opt.termguicolors = true
opt.clipboard = "unnamedplus"

-- The default border for every floating window that does not ask for one of its own.
-- Without it `K` (LSP hover) draws a borderless float that runs straight into the buffer
-- text behind it, with nothing marking where the popup ends.
--
-- One option rather than a `border` field per plugin, because core and all three float
-- providers here read it as their fallback: `vim.lsp.util.open_floating_preview` and
-- `vim.diagnostic`'s float in 0.11+, `snacks.win` (`lua/snacks/win.lua`), mini's modules,
-- and blink.cmp (`lib/window/utils.lua`'s `pick_border`). Anything that sets `border`
-- explicitly still wins -- this only fills the gap.
opt.winborder = "rounded"

-- One statusline for the whole editor rather than one per window. Set here rather than in
-- `lua/plugin/statusline.lua` because it is a Neovim option, not a plugin one --
-- mini.statusline has no say in it and simply fills whatever line this produces.
opt.laststatus = 3

-- Persist undo history between sessions.
opt.undofile = true

opt.splitbelow = true
opt.splitright = true

opt.ignorecase = true
opt.smartcase = true

opt.scrolloff = 8

-- One line per wheel notch instead of Neovim's default `ver:3`. Modern mice and
-- touchpads already emit a burst of wheel events per physical flick, and multiplying
-- each of those by three sends the view flying. The horizontal half drops from 6 to 2
-- for the same reason.
opt.mousescroll = { "ver:1", "hor:2", }

-- Folding is driven by tree-sitter, which sets `foldmethod` and `foldexpr` per buffer in
-- `lua/plugin/treesitter.lua`. These two are global because they are safe whether or not
-- a buffer has a parser.
--
-- Without `foldlevelstart` every file opens with every fold closed, which is startling.
opt.foldlevelstart = 99

-- An empty `foldtext` makes Neovim render a closed fold using the line's real syntax
-- highlighting, instead of the grey `+--  12 lines:` filler. Needs 0.10+.
opt.foldtext = ""

-- Indentation options are deliberately absent. Neovim's built-in EditorConfig
-- support is enabled by default and applies this repo's `.editorconfig` `[*.lua]`
-- rules (tabs, width 4) to Lua buffers on its own. Setting `expandtab` or
-- `shiftwidth` here would fight it. See `:help editorconfig`.
