-- Inline diagnostic messages, and the pickers for listing diagnostics.
--
-- Only the parts that need a plugin live here. The presentation itself is core
-- `vim.diagnostic` and sits in `lua/config/diagnostic.lua`.
--
-- Neovim has absorbed almost this entire plugin category, so most of the obvious
-- candidates are now redundant and, unsurprisingly, unmaintained: 0.11 made
-- `virtual_lines` a built-in handler, which is the whole of what `lsp_lines.nvim` was for
-- (last commit 2024-12-10, sourcehut only, no GitHub mirror), and added
-- `virtual_text.current_line`, which is what `diagflow.nvim` (stale since 2025-03) and
-- `error-lens.nvim` (stale since 2023-09) were for. `trouble.nvim` is alive but answers a
-- different question -- it is a list panel, which the snacks pickers below already cover.
--
-- What core still cannot express is the split this config wants: the full message on the
-- cursor line, a compact glyph on every other line that has a diagnostic. Core's
-- `current_line` options are all-or-nothing -- message on the cursor line, nothing
-- anywhere else. On top of that `virtual_lines` shifts code down as the cursor moves, and
-- `virtual_text` has no wrap option at all (there is no such field on
-- `vim.diagnostic.Opts.VirtualText`), so a long rust_analyzer message runs off the right
-- edge unreadable.
return {
	{
		"rachartier/tiny-inline-diagnostic.nvim",

		-- Both taken from upstream's own lazy.nvim snippet. `VeryLazy` is still early
		-- enough that no diagnostic has been published, and the priority keeps this ahead
		-- of anything else drawing virtual text on the same line.
		event    = "VeryLazy",
		priority = 1000,

		opts = {
			options = {
				add_messages = {
					-- The cursor-line/elsewhere split, and the reason this plugin is here.
					-- Off the cursor line the message collapses to a severity glyph and a
					-- count rather than disappearing entirely.
					display_count = true,
				},

				multilines = {
					-- Misleading name: this is not about multi-line *messages*, it is what
					-- permits anything to be drawn on lines the cursor is not on, which is
					-- the precondition upstream documents for `display_count`. Without
					-- both of these set, `display_count` silently does nothing.
					enabled     = true,
					always_show = true,
				},

				-- Wrap long messages instead of running them off the right edge. The one
				-- thing core's `virtual_text` cannot do.
				overflow = { mode = "wrap", },
			},
		},
	},

	{
		"folke/snacks.nvim",

		-- Global rather than buffer-local on LspAttach: diagnostics are not client-scoped,
		-- they can come from any source, and snacks is loaded eagerly so the picker is
		-- always available.
		--
		-- Note for anyone extending this file: do NOT add an `init` or `config` here.
		-- Several other files declare this same plugin, and lazy.nvim keeps only one of
		-- those functions -- see the comment in `lua/config/diagnostic.lua`.
		keys = {
			{
				"<leader>dd",
				function() require("snacks").picker.diagnostics_buffer() end,
				desc = "Diagnostics (buffer)",
			},
			{
				"<leader>dw",
				function() require("snacks").picker.diagnostics() end,
				desc = "Diagnostics (workspace)",
			},
		},
	},
}
