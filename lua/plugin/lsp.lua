return {
	{
		"mason-org/mason.nvim",
		opts = {},
		config = function()
			require("mason").setup({
				registries = {
					"github:mason-org/mason-registry",
					"github:Crashdummyy/mason-registry",
				},
			})
		end,
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
				"terraformls",
				"ts_ls",
			},
			automatic_enable = true,
		},
	},
	{
		"kosayoda/nvim-lightbulb",
	},
	{
		"ray-x/lsp_signature.nvim",
		event = "InsertEnter",
		opts = {},
	},
	{
		"smjonas/inc-rename.nvim",
		opts = {},
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
		"VidocqH/lsp-lens.nvim",
		opts = {
			sections = {
				git_authors = false,
				definition = function(count)
					if count > 1 then
						return "Definitions: " .. count
					end
				end,
				implements = function(count)
					if count > 1 then
						return "Implements: " .. count
					end
				end,
				references = function(count)
					if count > 0 then
						return "References: " .. count
					end
				end,
			},
		},
	},
	{
		"rachartier/tiny-inline-diagnostic.nvim",
		event = "VeryLazy",
		opts = {
		},
		config = function()
			require("tiny-inline-diagnostic").setup({
				options = {
					multilines = {
						enabled = true,
					},
				},
			})
		end,
	},
}
