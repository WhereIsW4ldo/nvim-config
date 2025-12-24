return {{
    'nvim-telescope/telescope.nvim',
      dependencies = { 
	      'nvim-lua/plenary.nvim',
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    opts = {
      defaults = {
        path_display = {shorten = 3},
        prompt_prefix = "> ",
      },
      extensions_list = {"fzf", "terms", "themes"},
    },
    }, 
    }
