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

-- The same four directions from inside a terminal buffer, so leaving a terminal is one
-- keystroke rather than <C-\><C-n> first and then the direction.
--
-- `<C-\><C-n>` is the terminal-mode escape hatch: it leaves terminal mode from anywhere,
-- including from a shell that has grabbed the keyboard, and unlike <Esc> it cannot be
-- swallowed by the program running in the pty. The window command then runs in normal mode.
--
-- The cost is that these four are no longer delivered to the shell. `<C-l>` (clear screen)
-- is the one actually worth noticing -- use the shell's `clear` instead. `<C-h>` is only a
-- loss on terminals that cannot distinguish it from <BS>; <BS> itself is untouched.
map("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Window: go left (from terminal)", })
map("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Window: go down (from terminal)", })
map("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Window: go up (from terminal)", })
map("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Window: go right (from terminal)", })

-- Ctrl-Backspace deletes the word before the cursor, the way the shell does.
--
-- It needs two spellings because the wire encoding differs. Terminals that speak the
-- kitty keyboard protocol -- ghostty here, also kitty, wezterm, foot -- send a distinct
-- code for Ctrl-BS and Neovim reports it as `<C-BS>`. Everything else collapses it onto
-- 0x08, which arrives as `<C-h>`: plain xterm, a `TERM=screen` tmux without passthrough,
-- an ssh session into a dumber terminal.
--
-- Only insert and command-line mode get both. Normal and terminal mode already spend
-- `<C-h>` on window navigation above, and that is the more valuable binding there.
for _, key in ipairs({ "<C-BS>", "<C-h>", }) do
	map("i", key, "<C-w>", { desc = "Delete word before cursor", })
	map("c", key, "<C-w>", { desc = "Delete word before cursor", })
end

-- Inside a terminal buffer nothing is deleted by Neovim; 0x17 (`<C-w>`) goes down the pty
-- and the shell's own backward-kill-word does the work.
map("t", "<C-BS>", "<C-w>", { desc = "Delete word before cursor (shell)", })

-- Plugin keymaps do NOT belong here. Declare them in the plugin's own spec under
-- `keys = { ... }` so lazy.nvim can defer loading the plugin until first use.
