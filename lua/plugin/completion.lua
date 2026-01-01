return {
	{
		"saghen/blink.cmp",
		dependencies = { "rafamadriz/friendly-snippets", },
		version = "1.*",
		build = "cargo build --release",

		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			-- All presets have the following mappings:
			-- C-space: Open menu or open docs if already open
			-- C-n/C-p or Up/Down: Select next/previous item
			-- C-e: Hide menu
			-- C-k: Toggle signature help (if signature.enabled = true)
			--
			-- See :h blink-cmp-config-keymap for defining your own keymap
			keymap = {
				preset = "default",

				["<C-n>"] = { "select_next", },
				["<C-p>"] = { "select_prev", },
				["<C-y>"] = { "select_and_accept", },
				["<C-space>"] = { "show", "show_documentation", "hide_documentation", },
				["<C-e>"] = { "hide", },
				["<C-k>"] = { "show_signature", "hide_signature", },
			},

			appearance = {
				nerd_font_variant = "mono",
			},

			completion = { documentation = { auto_show = true, }, },

			-- Default list of enabled providers defined so that you can extend it
			-- elsewhere in your config, without redefining it, due to `opts_extend`
			sources = {
				default = { "lsp", "easy-dotnet", "path", "snippets", "buffer", },
				providers = {
					["easy-dotnet"] = {
						name = "easy-dotnet",
						enabled = true,
						module = "easy-dotnet.completion.blink",
						score_offset = 10000,
						async = true,
					},
				},
			},

			fuzzy = { implementation = "prefer_rust_with_warning", },
		},
		opts_extend = { "sources.default", },
	},
}
