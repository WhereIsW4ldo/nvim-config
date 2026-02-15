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
				"tailwindcss",
				"vtsls",
				"powershell_es",
				"vue_ls",
			},
			automatic_enable = true,
			automatic_installation = true,
		},
		config = function(_, opts)
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						workspace = {
							library = vim.api.nvim_get_runtime_file("", true),
						},
					},
				},
			})

			vim.lsp.config("roslyn", {
				on_attach = function()
					print("Roslyn attached")
				end,
				settings = {
					["csharp|inline_hints"] = {
						csharp_enable_inlay_hints_for_implicit_object_creation = true,
						csharp_enable_inlay_hints_for_implicit_variable_types = true,
					},
					["csharp|code_lens"] = {
						dotnet_enable_references_code_lens = true,
					},
				},
			})

			vim.lsp.config("vtsls", {
				filetypes = {
					"typescript",
					"javascript",
					"javascriptreact",
					"typescriptreact",
					"vue",
				},
				settings = {
					vtsls = {
						tsserver = {
							globalPlugins = {
								{
									name = "@vue/typescript-plugin",
									location = vim.fn.stdpath("data")
										.. "/mason/packages/vue-language-server/node_modules/@vue/typescript-plugin",
									languages = { "vue" },
									configNamespace = "typescript",
									enableForWorkspaceTypeScriptVersions = true,
								},
							},
						},
					},
				},
			})

			require("mason-lspconfig").setup(opts)
		end,
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
		opts = {},
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
	{
		"TheLeoP/powershell.nvim",
		opts = {
			bundle_path = vim.fn.stdpath("data") .. "/mason/packages/powershell-editor-services",
		},
	},
	{
		"seblyng/roslyn.nvim",
		---@module 'roslyn.config'
		---@type RoslynNvimConfig
		opts = {
			filewatching = "roslyn",
		},
	},
}
