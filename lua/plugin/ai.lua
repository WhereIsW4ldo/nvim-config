-- opencode.nvim drives the `opencode` TUI in a snacks terminal split and sends it editor
-- context as references (`@path:Lstart-Lend`) rather than pasted text, so the agent reads
-- the code from disk and knows where it came from. Save before asking: it reads the file.
-- Providers (GitHub Copilot, OpenCode Go) are configured in opencode itself via `/connect`.
local cmd = "opencode"

local win = {
	position = "right",
	enter    = false,
	bo       = { buflisted = false, },
}

return {
	"nickjvandyke/opencode.nvim",
	dependencies = { "folke/snacks.nvim", },
	init = function()
		vim.g.opencode_opts = {
			server = {
				start = function()
					require("snacks.terminal").open(cmd, { win = win, })
				end,
			},
		}
	end,
	keys = {
		{
			"<leader>aa",
			function()
				require("snacks.terminal").toggle(cmd, { win = win, })
			end,
			-- A terminal-mode leader mapping buffers every typed Space until `timeoutlen`.
			-- Leave terminal mode with <C-\><C-n> before using this shortcut instead.
			mode = "n",
			desc = "AI: toggle OpenCode",
		},
		{
			"<leader>ak",
			function()
				require("opencode").ask("@this: ")
			end,
			mode = { "n", "x", },
			desc = "AI: ask OpenCode about selection/cursor",
		},
		{
			"<leader>as",
			function()
				require("opencode").select()
			end,
			mode = { "n", "x", },
			desc = "AI: OpenCode prompts and actions",
		},
		{
			"<leader>ao",
			function()
				return require("opencode").operator("@this ")
			end,
			mode = { "n", "x", },
			expr = true,
			desc = "AI: send range to OpenCode",
		},
		{
			"<leader>aO",
			function()
				return require("opencode").operator("@this ") .. "_"
			end,
			expr = true,
			desc = "AI: send line to OpenCode",
		},
	},
}
