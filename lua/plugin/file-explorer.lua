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
	    },
      -- on_attach = function(bufnr)
      --   local api = require('nvim-tree.api')
      --
      --   local function opts(desc)
      --     return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
      --   end
      --
      --   vim.keymap.set('n', 'A', function()
      --     local node = api.tree.get_node_under_cursor()
      --     local path = node.type == "directory" and node.absolute_path or vim.fs.dirname(node.absolute_path)
      --     require("easy-dotnet").create_new_item(path)
      --   end, opts('Create file from dotnet template'))
      -- end
    })
  end,
}
