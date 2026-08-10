-- The fuzzy finder: `snacks.picker`, bound.
--
-- `lua/plugin/ui.lua` already turns the picker on, but only as plumbing -- it is there so
-- `ui_select = true` has something to render `vim.ui.select` into. `lua/plugin/lsp.lua`
-- and `lua/plugin/diagnostic.lua` then call individual sources from their own keymaps.
-- What was missing is the picker as a thing you drive directly: no way to open a file by
-- name, grep the project, or switch buffers. This file is only that -- keymaps, no `opts`.
--
-- Everything sits under `<leader>f` (Find). The conventional split elsewhere is `<leader>f`
-- for files and `<leader>s` for search, which is not available here: `<leader>s` sources
-- the current file (`config/keymap.lua`) and that is the inner loop when editing this
-- config. One namespace for both halves is the smaller compromise.
--
-- Two `g`-prefixed pickers deliberately stay out of this namespace, because core Neovim
-- already names them and `lsp.lua` only swaps their UI: `gO` for document symbols (the
-- buffer-scoped counterpart of `<leader>fs` below) and `grr` for references.
--
-- Worth knowing inside any of these, since none of it is discoverable from the prompt:
--
--   <a-h> / <a-i>  include hidden / gitignored files -- both are excluded by default
--   <c-g>          in grep, switch between live `rg` and fuzzy-filtering the results
--   <c-t>          open in a new tab; <c-s> / <c-v> horizontal / vertical split
--   <Tab>          multi-select; <c-q> then sends the selection -- or, with nothing
--                  selected, the whole list -- to the quickfix window
--
-- `grep` needs the `rg` binary and has no fallback -- see README.md. File finding degrades
-- to `find` on its own, so `<leader>ff` keeps working where `<leader>fg` silently would
-- not.
return {
	"folke/snacks.nvim",

	-- No `lazy` / `priority`, and no `picker` opts: `lua/plugin/ui.lua` owns both, and
	-- restating them here would only create a second place to disagree.

	-- Sources are named as strings rather than passed as function values so the picker
	-- module itself stays unloaded until a key is actually pressed -- the same reason
	-- `lsp.lua` indirects through `require`.
	keys = {
		{
			"<leader>ff",
			function() require("snacks").picker.files() end,
			desc = "Find: files",
		},
		{
			"<leader>fg",
			function() require("snacks").picker.grep() end,
			desc = "Find: grep",
		},
		{
			"<leader>fb",
			function() require("snacks").picker.buffers() end,
			desc = "Find: buffers",
		},
		{
			-- `v:oldfiles`, so this survives a restart -- but only for files that were
			-- open when Neovim last exited cleanly, since that is when shada is written.
			"<leader>fr",
			function() require("snacks").picker.recent() end,
			desc = "Find: recent files",
		},
		{
			"<leader>fh",
			function() require("snacks").picker.help() end,
			desc = "Find: help tags",
		},
		{
			-- Workspace-wide, and therefore only as good as the attached server: it is a
			-- `workspace/symbol` request, which several servers answer only for symbols in
			-- files they have already indexed. `gO` is the reliable buffer-local one.
			"<leader>fs",
			function() require("snacks").picker.lsp_workspace_symbols() end,
			desc = "Find: workspace symbols",
		},
		{
			-- Capital `R` because `<leader>fr` is worth more as recent-files: resume is
			-- reached for after a mis-aimed `<CR>`, not many times an hour. Restores the
			-- last picker with its query, its filter toggles and its cursor position.
			"<leader>fR",
			function() require("snacks").picker.resume() end,
			desc = "Find: resume last picker",
		},
	},
}
