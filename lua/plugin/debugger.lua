return {
  {
    "mfussenegger/nvim-dap",
    enabled = true,
    dependencies = {
      "jbyuki/one-small-step-for-vimkind",
      "nvim-neotest/nvim-nio",
      "rcarriga/nvim-dap-ui",
    },
  },
  {
    "rcarriga/nvim-dap-ui",
    opts = {
      icons = { expanded = "", collapsed = "", current_frame = "" },
      mappings = {
        expand = { "<CR>" },
        open = "o",
        remove = "d",
        edit = "e",
        repl = "r",
        toggle = "t",
      },
      element_mappings = {},
      expand_lines = true,
      force_buffers = true,
      layouts = {
        {
          elements = {
            { id = "scopes", size = 1 },
            -- {
            --   id = "repl",
            --   size = 0.66,
            -- },
          },

          size = 10,
          position = "bottom",
        },
        {
          elements = {
            "breakpoints",
            -- "console",
            "stacks",
            "watches",
          },
          size = 45,
          position = "right",
        },
      },
      floating = {
        max_height = nil,
        max_width = nil,
        border = "single",
        mappings = {
          ["close"] = { "q", "<Esc>" },
        },
      },
      controls = {
        enabled = vim.fn.exists "+winbar" == 1,

        element = "repl",
        icons = {
          pause = "",
          play = "",
          step_into = "",
          step_over = "",
          step_out = "",
          step_back = "",
          run_last = "",
          terminate = "",
          disconnect = "",
        },
      },
      render = {
        max_type_length = nil, -- Can be integer or nil.
        max_value_lines = 100, -- Can be integer or nil.
        indent = 1,
      },
    }
  }
}
