-- Copilot CLI agent integration, without inline completion or Next Edit Suggestions.
return {
	"folke/sidekick.nvim",
	dependencies = { "folke/snacks.nvim", },
	cmd = "Sidekick",
	opts = {
		nes     = { enabled = false, },
		copilot = { status = { enabled = false, }, },
		cli     = {
			mux = { enabled = false, },
		},
	},
	keys = {
		{
			"<leader>aa",
			function() require("sidekick.cli").toggle({ name = "copilot", focus = true, }) end,
			desc = "AI: toggle Copilot agent",
		},
		{
			"<leader>av",
			function()
				require("sidekick.cli").send({
					name   = "copilot",
					msg    = "{selection}",
					focus  = true,
					submit = false,
				})
			end,
			mode = "x",
			desc = "AI: send selection to Copilot",
		},
		{
			"<leader>af",
			function()
				require("sidekick.cli").send({
					name   = "copilot",
					msg    = "{file}",
					focus  = true,
					submit = false,
				})
			end,
			desc = "AI: send file to Copilot",
		},
		{
			"<leader>ap",
			function()
				require("sidekick.cli").prompt({
					cb = function(_, text)
						if text then
							require("sidekick.cli").send({
								name   = "copilot",
								text   = text,
								focus  = true,
								submit = false,
							})
						end
					end,
				})
			end,
			mode = { "n", "x", },
			desc = "AI: Copilot prompt library",
		},
	},
}
