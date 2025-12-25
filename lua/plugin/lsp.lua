return {
  {
    "mason-org/mason.nvim",
    opts = {}
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
        "mason-org/mason.nvim",
        "neovim/nvim-lspconfig",
    },
    opts = {
      ensure_installed = {
        "arduino_language_server",
        "azure_pipelines_ls",
        "bashls",
        "cssls",
        "docker_compose_language_service",
        "docker_language_server",
        "eslint",
        "html",
        "jsonls",
        "lua_ls",
        "rust_analyzer",
        "svelte",
        "ts_ls"
      }
    },
  },
  {
   'kosayoda/nvim-lightbulb'
  },
  {
    "ray-x/lsp_signature.nvim",
    event = "InsertEnter",
    opts = {}
  },
  {
    "smjonas/inc-rename.nvim",
    opts = {}
  },
  {
    "jubnzv/virtual-types.nvim",
  },
  {
    "aznhe21/actions-preview.nvim",
  },
  {
    "j-hui/fidget.nvim",
    opts = {},
  },
  {
    'VidocqH/lsp-lens.nvim',
    opts = {
      sections = {
        git_authors = false
      }
    }
  },
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "VeryLazy",
    opts = {},
  },
}
