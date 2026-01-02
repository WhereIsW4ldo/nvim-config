return {
	{
		"nvim-telescope/telescope.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope-fzf-native.nvim",
			build = "make",
		},
		opts = {
			defaults = {
				path_display = { shorten = 3, },
				prompt_prefix = "> ",
				theme = "dropdown",
			},
			extensions_list = { "fzf", "terms", "themes", },
		},
		config = function()
			require("telescope").setup({
				defaults = require("telescope.themes").get_dropdown(),
			})
		end,
	},
}
