-- Project-wide find/replace with a live diff, in a regular Neovim split.
-- `<leader>fr` is recent files; `<leader>s` sources the current file, so use `fp`.
return {
	"MagicDuck/grug-far.nvim",
	cmd = { "GrugFar", "GrugFarWithin", },
	opts = {
		-- The structural-search engines need a separate, optional ast-grep executable.
		enabledEngines = { "ripgrep", },
	},
	keys = {
		{
			"<leader>fp",
			function()
				local root = vim.fs.root(0, { ".git", }) or vim.fn.getcwd()

				-- Make the scope visible without changing the editor's working directory.
				-- In visual mode, upstream also prefills Search from the selection.
				require("grug-far").open({ prefills = { paths = root:gsub(" ", "\\ "), }, })
			end,
			mode = { "n", "x", },
			desc = "Find: replace in project",
		},
	},
}
