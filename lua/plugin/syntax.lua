return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local treesitter = require("nvim-treesitter")

			treesitter.setup({})
			treesitter.install({ 
				'arduino',
				'bash',
				'c',
				'c_sharp',
				'cmake',
				'cpp',
				'css',
				'csv',
				'dockerfile',
				'editorconfig',
				'fsharp',
				'gdscript',
				'go',
				'graphql',
				'haskell',
				'html',
				'javascript',
				'json',
				'lua',
				'make',
				'markdown',
				'pod',
				'powershell',
				'python',
				'razor',
				'regex',
				'rust',
				'sql',
				'svelte',
				'terraform',
				'typescript',
				'vue',
				'zig',
				'zsh'
			})
		end
	}
}
