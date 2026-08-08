local map = vim.keymap.set

-- Reload the file currently being edited. This is the main loop when iterating on
-- this config.
map("n", "<leader>s", "<Cmd>source %<CR>", { desc = "Source current file", })

-- Drop the search highlight without clobbering the last-search register.
map("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlight", })

-- Keep the cursor centred when paging, so the eye does not have to re-find it.
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centred)", })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centred)", })

-- Move through wrapped lines by screen line unless a count was given.
map("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true, desc = "Down (screen line)", })
map("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true, desc = "Up (screen line)", })

-- Window navigation, following the usual `hjkl` directions.
--
-- Note `<C-l>` normally redraws the screen; `:redraw!` still does that if needed.
map("n", "<C-h>", "<C-w>h", { desc = "Window: go left", })
map("n", "<C-j>", "<C-w>j", { desc = "Window: go down", })
map("n", "<C-k>", "<C-w>k", { desc = "Window: go up", })
map("n", "<C-l>", "<C-w>l", { desc = "Window: go right", })

-- Plugin keymaps do NOT belong here. Declare them in the plugin's own spec under
-- `keys = { ... }` so lazy.nvim can defer loading the plugin until first use.
