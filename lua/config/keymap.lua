local keymap = vim.keymap

-- navigation
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window", remap = true })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window", remap = true })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window", remap = true })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", remap = true })

-- window size adjustments
keymap.set("n", "<C-Up>", "<cmd>resize -2<cr>", { desc = "Increase Window Height" })
keymap.set("n", "<C-Down>", "<cmd>resize +2<cr>", { desc = "Decrease Window Height" })
keymap.set("n", "<C-Left>", "<cmd>vertical resize +2<cr>", { desc = "Decrease Window Width" })
keymap.set("n", "<C-Right>", "<cmd>vertical resize -2<cr>", { desc = "Increase Window Width" })

-- Keep visual indenting selected after indenting
keymap.set("v", "<", "<gv")
keymap.set("v", ">", ">gv")

-- Terminal keymaps
keymap.set("t", "<leader><Esc>", "<C-\\><C-n>", { noremap = true, silent = true })
-- keymap.set("t", "<C-/>", function()
-- 	require("snacks").terminal()
-- end, { desc = "Togglet Terminal" })

keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Exit terminal and go to Left Window", remap = true })
keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Exit terminal and go to Lower Window", remap = true })
keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Exit terminal and go to Upper Window", remap = true })
keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Exit terminal and go to Right Window", remap = true })

-- file explorer
local explorer = require('nvim-tree.api')

keymap.set('n',	'<C-n>', 
	function () 
		explorer.tree.toggle({
			find_file = true,
			focus = false
		}) 
	end, 
	{ desc = '📁 Open file explorer', remap = true }
) 

local telescope = require('telescope.builtin')

keymap.set('n', '<C-t>', telescope.find_files, { desc = '🔍 Find files' })
keymap.set('n', '<C-F>', telescope.live_grep, { desc = '🔍 Grep in files' })

