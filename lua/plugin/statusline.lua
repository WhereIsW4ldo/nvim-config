return {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      local dotnet_job_indicator = { require('easy-dotnet.ui-modules.jobs').lualine }

      require('lualine').setup({
        sections = {
          lualine_a = { 'mode', dotnet_job_indicator },
        }
      })
    end
}
