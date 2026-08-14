-- Other occurrences of the symbol under the cursor, highlighted as you move.
--
-- `vim-illuminate`, chosen for its provider cascade: it asks the language server first
-- (`textDocument/documentHighlight`, so a shadowed local in a nested scope is correctly
-- a different symbol) and falls back to a plain regex match. The first provider that
-- answers wins, per buffer.
--
-- Two providers, not the three the README advertises. Its `treesitter` provider is
-- deliberately left out, and would do nothing if added: it requires the
-- `nvim-treesitter.locals` module, which exists only on nvim-treesitter's `master`
-- branch. `lua/plugin/treesitter.lua` tracks `main`, where the rewrite removed it, so
-- the provider's `pcall(require, ...)` fails and it falls through to regex regardless.
-- The plugin's own default `providers` is already `{ "lsp", "regex" }` for this reason
-- (`lua/illuminate/config.lua`); the README's default block is stale.
--
-- Chosen over three alternatives that all cost less:
--   * `snacks.words` -- already installed, so free, but LSP-only. Nothing at all happens
--     in a buffer with no attached server, which here is every JSON, log or plain-text
--     file, plus any file opened before its server finishes starting.
--   * `local-highlight.nvim` -- regex only, over visible lines only. Faster on huge
--     files, but it cannot tell a variable from the same letters inside a comment.
--   * `mini.cursorword` -- the same textual match, and mini.nvim is already installed
--     here for the statusline, so it would also have been free. Ruled out for the same
--     reason: `<cword>` string matching with no semantic layer above it.
--
-- Ruled out on facts rather than taste: `sontungexpt/stcursorword` (no push since
-- 2025-11-30), `akioweh/lsp-document-highlight.nvim` (11 stars, unproven), and
-- `ya2s/nvim-cursorline`, which bundles cursorline dimming that was not asked for.
--
-- No entry in `install.sh`: this is pure Lua with no external toolchain. The treesitter
-- provider uses parsers `lua/plugin/treesitter.lua` already installs, and the LSP
-- provider uses the servers `lua/plugin/lsp.lua` already installs -- neither is a new
-- dependency, and both degrade to the regex provider when absent.
--
-- Catppuccin styles `IlluminatedWordText` / `Read` / `Write` through its `illuminate`
-- integration, which `lua/plugin/colorscheme.lua` picks up automatically via
-- `auto_integrations`. Nothing needs adding there -- but note that catppuccin compiles
-- its highlights to `~/.cache/nvim/catppuccin/` and does not invalidate that cache when
-- a new plugin appears. Until the cache is rebuilt, these three groups are absent and
-- illuminate falls back to its own default of a bare underline. Deleting the directory
-- is enough; the next start recompiles it.
return {
	"RRethy/vim-illuminate",

	-- Illumination is wired per buffer from `plugin/illuminate.vim`, so the plugin has to
	-- be on the runtimepath by the time the first real file is read. `VeryLazy` fires
	-- after that for a file named on the command line, which would leave that first
	-- buffer unilluminated until it was left and re-entered.
	event = { "BufReadPost", "BufNewFile", },

	-- Upstream's own lhs, restated here only to attach a `desc` to each. The plugin sets
	-- these itself when `disable_keymaps` is false, but leaves the textobject without a
	-- description, so it shows up blank in which-key and in `:map`.
	keys = {
		{
			"<a-n>",
			function() require("illuminate").goto_next_reference() end,
			desc = "Next reference",
		},
		{
			"<a-p>",
			function() require("illuminate").goto_prev_reference() end,
			desc = "Previous reference",
		},
		{
			"<a-i>",
			function() require("illuminate").textobj_select() end,
			mode = { "o", "x", },
			desc = "Reference under the cursor",
		},
	},

	-- `config` rather than `opts`, against this repo's usual preference, because there is
	-- nothing for `opts` to call: the module exposes `configure`, not `setup`, and
	-- lazy.nvim's default handler calls the latter unconditionally.
	config = function()
		require("illuminate").configure({
			-- Illuminate only ever filters on filetype, so a `nofile` scratch buffer --
			-- the snacks picker list, the explorer sidebar, a notification history -- is
			-- fair game to it unless something says otherwise. Keying on `buftype`
			-- instead of naming those filetypes means the rule does not rot when snacks
			-- renames one of them.
			--
			-- Despite the README calling this an override of all other settings, the
			-- engine ANDs it with the filetype and mode lists (`engine.lua`,
			-- `buf_should_illuminate`). So it can only ever veto, never re-enable, and
			-- the default denylist of `dirbuf` / `dirvish` / `fugitive` stays in force
			-- underneath it.
			should_enable = function(bufnr)
				return vim.bo[bufnr].buftype == ""
			end,

			disable_keymaps = true,
		})
	end,
}
