return {
	"stevearc/oil.nvim",
	---@module 'oil'
	---@type oil.setupOpts
	opts = {
		keymaps = {
			["<BS>"] = { "actions.parent", mode = "n", },
			["<leader>h"] = { "actions.toggle_hidden", mode = "n", },
		},
	},
	dependencies = { "nvim-mini/mini.icons", },
	lazy = false,
}
