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

-- search
local telescope = require('telescope.builtin')

keymap.set('n', '<C-t>', telescope.find_files, { desc = '🔍 Find files' })
keymap.set('n', '<C-F>', telescope.live_grep, { desc = '🔍 Grep in files' })

-- git
keymap.set('n', '<leader>gg', "<cmd>LazyGit<cr>", { desc = 'Git' })

-- terminal
keymap.set({ "n", "t" }, "<C-_>", "<cmd>ToggleTerm<cr>", { desc = "🖥️ Terminal" })
keymap.set({ "n", "t" }, "<C-/>", "<cmd>ToggleTerm<cr>", { desc = "🖥️ Terminal" })
keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Exit terminal and go to Left Window", remap = true })
keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Exit terminal and go to Lower Window", remap = true })
keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Exit terminal and go to Upper Window", remap = true })
keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Exit terminal and go to Right Window", remap = true })

-- LSP
keymap.set("n", "<C-r>r", function()
  return ":IncRename " .. vim.fn.expand("<cword>")
end, { expr = true })
keymap.set({ "v", "n" }, "<leader>ca", require('actions-preview').code_actions, { desc = "Code action" })
keymap.set("n", "<leader>fr", telescope.lsp_references, { desc = 'LSP References' })
keymap.set("n", "<leader>fi", telescope.lsp_implementations, { desc = 'LSP Implementations' })
keymap.set("n", "<leader>fd", telescope.lsp_type_definitions, { desc = 'LSP Type Definitions' })
