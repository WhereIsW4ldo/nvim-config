local keymap = vim.keymap

-- temp
keymap.set("n", "<leader>s", "<cmd>so %<CR>", { desc = "Execute current .lua file", })

-- navigation
keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window", remap = true, })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window", remap = true, })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window", remap = true, })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", remap = true, })

-- file
keymap.set("n", "<leader>o", "<CMD>Oil<CR>", { desc = "Open parent directory ", })

-- window size adjustments
keymap.set("n", "<C-Up>", "<cmd>resize -2<cr>", { desc = "Increase Window Height", })
keymap.set("n", "<C-Down>", "<cmd>resize +2<cr>", { desc = "Decrease Window Height", })
keymap.set("n", "<C-Left>", "<cmd>vertical resize +2<cr>", { desc = "Decrease Window Width", })
keymap.set("n", "<C-Right>", "<cmd>vertical resize -2<cr>", { desc = "Increase Window Width", })

-- Keep visual indenting selected after indenting
keymap.set("v", "<", "<gv")
keymap.set("v", ">", ">gv")

-- search
local telescope = require("telescope.builtin")

keymap.set("n", "<C-t>", telescope.find_files, { desc = "🔍 Find files", })
keymap.set("n", "<C-F>", telescope.live_grep, { desc = "🔍 Grep in files", })

-- git
keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { desc = "Git", })

-- terminal
keymap.set({ "n", "t", }, "<C-_>", "<cmd>ToggleTerm<cr>", { desc = "🖥️ Terminal", })
keymap.set({ "n", "t", }, "<C-/>", "<cmd>ToggleTerm<cr>", { desc = "🖥️ Terminal", })
keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Exit terminal and go to Left Window", remap = true, })
keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Exit terminal and go to Lower Window", remap = true, })
keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Exit terminal and go to Upper Window", remap = true, })
keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Exit terminal and go to Right Window", remap = true, })

-- LSP
keymap.set("n", "<C-r>r", function()
	return ":IncRename " .. vim.fn.expand("<cword>")
end, { expr = true, })
keymap.set({ "v", "n", }, "<leader>ca", require("actions-preview").code_actions, { desc = "Code action", })
keymap.set("n", "<leader>fr", telescope.lsp_references, { desc = "LSP References", })
keymap.set("n", "<leader>fi", telescope.lsp_implementations, { desc = "LSP Implementations", })
keymap.set("n", "<leader>fd", telescope.lsp_type_definitions, { desc = "LSP Type Definitions", })
keymap.set("n", "<leader>m", require("treesj").toggle, { desc = "(Un)fold list", })

-- Code editor
keymap.set({ "n", "x", "o", }, "s", function() require("flash").jump() end, { desc = "📸 Flash", })
keymap.set({ "n", "x", "o", }, "S", function() require("flash").treesitter() end, { desc = "📸 Flash Treesitter", })
keymap.set("o", "r", function() require("flash").remote() end, { desc = "📸 Remote Flash", })
keymap.set({ "o", "x", }, "R", function() require("flash").treesitter_search() end, { desc = "📸 Treesitter Search", })
keymap.set({ "c", }, "<C-s>", function() require("flash").toggle() end, { desc = "📸 Toggle Flash Search", })

-- Debugger
local dap = require("dap")
dap.set_log_level("TRACE")
local dapui = require("dapui")

dap.configurations.lua = {
	{
		type = "nlua",
		request = "attach",
		name = "Attach to running Neovim instance",
	},
}

dap.adapters.nlua = function(callback, config)
	callback({ type = "server", host = config.host or "127.0.0.1", port = config.port or 8086, })
end

dap.listeners.after.event_stopped["dap_ui"] = function()
	dapui.open()
end

dap.listeners.on_session["dap_ui"] = function(_, new)
	if new == nil then
		dapui.close()
	end
end

vim.keymap.set("n", "<F5>", dap.continue, {})

vim.keymap.set("n", "<leader>dl", function()
	require("osv").launch({ port = 8086, })
end, { desc = "Debugger launch (OSV)", })

vim.keymap.set("n", "<leader>dq", function()
	dap.close()
end, {})
vim.keymap.set("n", "<F10>", dap.step_over, {})
vim.keymap.set("n", "<leader>dO", dap.step_over, {})
vim.keymap.set("n", "<leader>dC", dap.run_to_cursor, {})
vim.keymap.set("n", "<leader>dr", dap.repl.toggle, {})
vim.keymap.set("n", "<leader>dj", dap.down, {})
vim.keymap.set("n", "<leader>dk", dap.up, {})
vim.keymap.set("n", "<F11>", dap.step_into, {})
vim.keymap.set("n", "<F12>", dap.step_out, {})
vim.keymap.set("n", "<leader>b", dap.toggle_breakpoint, {})
vim.keymap.set("n", "<F2>", require("dap.ui.widgets").hover, {})

vim.cmd("hi DapBreakpointColor guibg=#442723")
vim.cmd("hi DapStoppedColor guibg=#684C1C")

vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "", linehl = "DapBreakpointColor", numhl = "", })
vim.fn.sign_define("DapStopped", { text = "", texthl = "", linehl = "DapStoppedColor", numhl = "", })
