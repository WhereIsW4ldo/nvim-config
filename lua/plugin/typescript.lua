-- TypeScript and Vue, which are one concern rather than two.
--
-- Vue language server v3 dropped takeover mode: `vue_ls` now handles only the CSS/HTML
-- of a single-file component and hands the `<script>` block to a TypeScript server. That
-- server has to be `vtsls` (or `ts_ls`) running `@vue/typescript-plugin` -- so Vue's
-- TypeScript support is literally a `vtsls` setting, and lives here.
--
-- `vue_ls` itself needs nothing beyond its `ensure_installed` entry in
-- `lua/plugin/lsp.lua`; nvim-lspconfig's own `lsp/vue_ls.lua` already knows how to find
-- whichever TypeScript client is attached to the buffer.
--
-- The spec targets nvim-lspconfig rather than declaring a plugin of its own, because
-- lazy.nvim merges specs for the same repo. That merge has one sharp edge worth knowing:
-- `opts` and the lazy-loading triggers are merged, but a function field is not -- the last
-- spec to define one silently wins. `lua/plugin/lsp.lua` owns `init` on this plugin, so
-- this file uses `config`. **One file per hook, or the other file's hook disappears.**
--
-- `config` is early enough: nvim-lspconfig is a dependency of mason-lspconfig, so it loads
-- first, and in any case `vim.lsp.config` only has to beat the first buffer to a client.
return {
	"neovim/nvim-lspconfig",

	config = function()
		-- The plugin ships inside the `vue-language-server` mason package, so its path is
		-- mason's install root and not something to install separately. Built from
		-- `stdpath("data")` rather than `$MASON`, which mason only exports once loaded.
		local vue_language_server = vim.fs.joinpath(
			vim.fn.stdpath("data"),
			"mason", "packages", "vue-language-server", "node_modules", "@vue/language-server"
		)

		vim.lsp.config("vtsls", {
			-- `vue` must appear here AND in `languages` below. This list is what makes
			-- vtsls attach to a `.vue` buffer at all; the other is what makes tsserver
			-- route those buffers through the plugin once it has.
			filetypes = {
				"javascript",
				"javascriptreact",
				"typescript",
				"typescriptreact",
				"vue",
			},

			settings = {
				-- Project-wide diagnostics. Off by default here as it is in VS Code, and the
				-- reason is that tsserver otherwise validates only files with an open buffer --
				-- an error introduced in a file since closed stays invisible until it is opened
				-- again, or until CI runs `tsc`.
				--
				-- With this on, diagnostics arrive for URIs that have no buffer. Neovim creates
				-- an unlisted one per URI to hold them, which is what puts them in
				-- `vim.diagnostic.get(nil)` and so in `<leader>dw`, the snacks workspace picker
				-- from `lua/plugin/diagnostic.lua`. Nothing is drawn inline until the file is
				-- actually opened, which is the point of it.
				--
				-- Two costs. tsserver holds and re-checks the whole program, which is real CPU
				-- and memory on a large monorepo. And vtsls#322 has it reporting on files inside
				-- `node_modules` regardless of `exclude` or `skipLibCheck` -- open as of writing.
				-- If that noise wins, this block is the thing to delete.
				--
				-- ESLint is NOT covered by it: `eslint_d` in `lua/plugin/lint.lua` runs over the
				-- current buffer only. This is the type checker's half of the project, no more.
				typescript = {
					tsserver = {
						experimental = {
							enableProjectDiagnostics = true,
						},
					},
				},

				vtsls = {
					tsserver = {
						globalPlugins = {
							{
								name            = "@vue/typescript-plugin",
								location        = vue_language_server,
								languages       = { "vue", },
								configNamespace = "typescript",
							},
						},
					},
				},
			},
		})
	end,
}
