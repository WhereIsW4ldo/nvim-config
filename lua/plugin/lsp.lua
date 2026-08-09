-- Language servers: installation, enablement, and the navigation keymaps.
--
-- Neovim 0.12 already provides most of the LSP surface -- `grn`, `gra`, `grr`, `gri`,
-- `grt`, `grx`, `gO`, `K`, `<C-s>`, `]d`/`[d` and `gq` are all default mappings, and
-- `vim.lsp.enable()` is core. So this file is deliberately thin: it installs servers,
-- lets them enable themselves, and swaps the quickfix window for a picker.
--
-- Servers are managed by mason, NOT by `install.sh`. That is a deliberate departure from
-- this repo's usual rule, recorded in CLAUDE.md's dependency bullet. The trade is
-- reproducibility for convenience -- mason has no lockfile, so server versions float and
-- `:Mason` then `U` updates them. `install.sh` still guarantees the toolchains mason
-- shells out to. If a floating version ever bites, `ensure_installed` accepts per-server
-- pinning (`"rust_analyzer@nightly"`) without adopting a lockfile.
--
-- An array of specs rather than one table, because these three are only useful together.
-- `lazydev.nvim`, which makes lua_ls aware of the Neovim runtime, lives in
-- `lua/plugin/lua.lua` instead -- it is Lua-specific, not part of the generic server
-- machinery here, and keeping it out is what keeps this file under the length that
-- signals a split.
return {
	{
		"mason-org/mason.nvim",

		-- Note the owner: mason moved to the `mason-org` organisation for v2. The
		-- `williamboman/*` paths are the v1 line and are not what this uses.
		opts = {},
	},

	{
		"mason-org/mason-lspconfig.nvim",

		-- mason must be set up before this runs, and nvim-lspconfig supplies the
		-- `lsp/<server>.lua` definitions that `vim.lsp.enable()` reads off the
		-- runtimepath. `dependencies` states that; relying on load order would not.
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
		},

		opts = {
			-- lspconfig server names, NOT mason package names -- translating between the
			-- two is precisely what this plugin exists for. `lua_ls` here is the mason
			-- package `lua-language-server`.
			--
			-- Adding a language means editing this list and the `languages` list in
			-- `lua/plugin/treesitter.lua`.
			ensure_installed = { "lua_ls", },

			-- Already the default. Stated because it is the reason no server is
			-- configured by hand anywhere in this config: mason-lspconfig calls
			-- `vim.lsp.enable()` for every installed server itself.
			automatic_enable = true,
		},
	},

	{
		"neovim/nvim-lspconfig",

		-- Buffer-local keymaps, set when a client attaches. They deliberately reuse
		-- Neovim's own key names -- nothing here is vocabulary you would have to unlearn
		-- elsewhere -- and change only the UI: core opens a quickfix window for
		-- multi-result jumps, these open the snacks picker, which previews and filters.
		--
		-- Buffer-local rather than global, so core's own global mappings remain the
		-- fallback in buffers with no client, where they explain themselves politely.
		--
		-- `gd` is the one genuinely absent mapping: core leaves go-to-definition on
		-- `<C-]>` via `tagfunc` and binds no `g`-prefixed key to it.
		init = function()
			local group = vim.api.nvim_create_augroup("waldo_lsp_attach", { clear = true, })

			vim.api.nvim_create_autocmd("LspAttach", {
				group = group,
				desc = "LSP navigation keymaps, backed by the snacks picker",
				callback = function(args)
					-- The picker is named rather than passed as a function value so the
					-- snacks picker module stays unloaded until a key is actually pressed.
					local function map(lhs, source, desc)
						vim.keymap.set("n", lhs, function()
							require("snacks").picker[source]()
						end, { buffer = args.buf, desc = desc, })
					end


					map("gd", "lsp_definitions", "Goto definition")
					map("grr", "lsp_references", "References")
					map("gri", "lsp_implementations", "Goto implementation")
					map("grt", "lsp_type_definitions", "Goto type definition")
					map("gO", "lsp_symbols", "Document symbols")
				end,
			})
		end,
	},
}
