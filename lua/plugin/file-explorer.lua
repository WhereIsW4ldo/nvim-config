return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  opts = {},
  config = function()
    require("nvim-tree").setup ({
	    actions = {
		    change_dir = {
			    enable = true,
			    global = true
		    }
	    }
    })
  end,
}
