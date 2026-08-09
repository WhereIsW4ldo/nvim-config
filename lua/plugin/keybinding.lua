-- Keybinding discovery: press a prefix and a popup lists the valid continuations.
--
-- Descriptions come from each mapping's own `desc` field, so nothing needs to be
-- registered here twice -- which is why CLAUDE.md requires a `desc` on every keymap.
-- The built-in key presets (operators, motions, text objects, `<C-w>`, `g`, `z`) and
-- the marks / registers / spelling popups are all enabled by default upstream, so
-- they are deliberately not restated below.
return {
	"folke/which-key.nvim",

	-- Nothing to show until the UI exists, and it must be loaded before a prefix is
	-- pressed -- so `VeryLazy` rather than a `keys` trigger.
	event = "VeryLazy",

	opts = {
		-- Only prefix *group* names need declaring; individual mappings are picked up
		-- automatically. Add a line here whenever a new `<leader>` namespace appears.
		spec = {
			{ "<leader>a", group = "AI", },
			{ "<leader>g", group = "Git", },
		},
	},

	keys = {
		{
			"<leader>?",
			function() require("which-key").show({ global = false, }) end,
			desc = "Buffer local keymaps",
		},
	},
}
