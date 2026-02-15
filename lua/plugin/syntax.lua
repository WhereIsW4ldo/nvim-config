return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local treesitter = require("nvim-treesitter")

			treesitter.setup({
				auto_install = true,
				highlight = {
					enable = true,
				},
			})

			-- Ensure Vue-related parsers are installed
			treesitter.install({ "vue", "typescript", "javascript", "html", "css" })
		end,
	},
	{
		"ya2s/nvim-cursorline",
		opts = {
			cursorline = {
				enable = true,
				timeout = 1000,
				number = false,
			},
			cursorword = {
				enable = true,
				min_length = 3,
				hl = { underline = true, },
			},
		},
	},
}
