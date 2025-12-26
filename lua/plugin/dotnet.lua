return {
  {
    "GustavEikaas/easy-dotnet.nvim",
    dependencies = { "nvim-lua/plenary.nvim", 'nvim-telescope/telescope.nvim', },
    config = function()
      local dotnet = require("easy-dotnet")

      dotnet.setup({
        lsp = {
          enabled = true,
          roslynator_enabled = true,
        },
        picker = "telescope",
        background_scanning = true,
      })
    end
  },
}
