-- How diagnostics are presented, and how to list them.
--
-- Neovim 0.12 defaults to `signs = true` and `underline = true` but leaves BOTH
-- `virtual_text` and `virtual_lines` false -- so a diagnostic is a squiggle and a gutter
-- sign with no readable message unless you press `<C-w>d`. That is the gap here.
--
-- This returns a snacks.nvim spec. lazy.nvim merges specs for the same plugin across
-- import files, so it adds to the one in `lua/plugin/ui.lua` rather than competing with
-- it. The file is named for the concern rather than the plugin because the plugin is
-- incidental -- the presentation half is core `vim.diagnostic`, and it lives here rather
-- than in `lua/config/` only because the pickers below need snacks, which would make
-- `config/` depend on a plugin.
return {
	"folke/snacks.nvim",

	-- `init`, not `config`: this is core API that does not need snacks loaded, and the
	-- presentation should be settled before the first diagnostic is ever published.
	init = function()
		vim.diagnostic.config({
			-- Only on the line the cursor is on. Full `virtual_lines` shifts code down
			-- for every diagnostic on screen, and `virtual_text` truncates long messages
			-- and clutters. This shows the entire message exactly where you are looking,
			-- and nothing anywhere else.
			virtual_lines = { current_line = true, },

			-- So an error outranks a warning for the single sign the gutter can show.
			severity_sort = true,
		})
	end,

	-- Global rather than buffer-local on LspAttach: diagnostics are not client-scoped,
	-- they can come from any source, and snacks is loaded eagerly so the picker is
	-- always available.
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
}
