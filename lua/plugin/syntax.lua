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
	},
  {
    'ya2s/nvim-cursorline',
    opts = {
      cursorline = {
        enable = true,
        timeout = 1000,
        number = false,
      },
      cursorword = {
        enable = true,
        min_length = 3,
        hl = { underline = true },
      }
    }
  }
}
