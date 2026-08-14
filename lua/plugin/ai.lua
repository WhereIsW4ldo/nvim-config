-- Claude Code, over the WebSocket + MCP protocol Anthropic's own VS Code and JetBrains
-- extensions speak. The plugin stands up an RFC 6455 server on a random port, writes
-- `~/.claude/ide/<port>.lock`, and sets `CLAUDE_CODE_SSE_PORT` / `ENABLE_IDE_INTEGRATION`
-- so the CLI it launches in a terminal buffer discovers Neovim and connects back to it.
-- That back-channel is what makes native diffs, at-mention sends and file-open-from-Claude
-- work; the protocol is documented in the repo's `PROTOCOL.md`.
--
-- Replaces `carlos-algms/agentic.nvim`, which drove the same CLI over the Agent Client
-- Protocol through the `@agentclientprotocol/claude-agent-acp` npm bridge. ACP is a
-- vendor-neutral protocol, so it carries the intersection of what every agent does rather
-- than everything Claude Code does, and the bridge lags each release: agentic's own tracker
-- has the shape of it -- restored sessions losing their mode and model (#310), and no way to
-- surface Claude Code's `AskUserQuestion` because ACP does not model it (#274).
--
-- Here the real `claude` TUI runs in the terminal, so there is no feature to fall behind on:
-- mode cycling, `/model`, skills, and whatever ships next all work because they are not
-- reimplemented. Auth is likewise unchanged -- the CLI's own `claude /login` session.
--
-- What that costs, stated plainly, since all three were configured deliberately before:
--
--   * ONE SESSION AT A TIME. agentic ran several concurrently and kept them alive behind a
--     closed window. Here there is a single Claude terminal; `--resume` picks a different
--     session rather than adding one, and resuming while one is live means stopping it
--     first. Tracked upstream but unimplemented (issues #187, #177, #147).
--   * NO NEOVIM-NATIVE CHAT BUFFER, so no foldable tool calls -- the `folding.tool_calls`
--     tuning has no equivalent, because the CLI renders its own output. Diffs are the
--     exception: those come over the protocol and open as real Neovim windows.
--   * MODEL SWITCHING IS LAUNCH-TIME. `<leader>am` restarts the CLI with `--model`; there
--     is no mid-conversation picker. `/model` inside the TUI is the live route.
--
-- Diagnostics are no longer pushed either, which is a change in direction rather than a
-- loss: `<leader>ad` / `<leader>aD` are gone because Claude pulls diagnostics itself through
-- the MCP `getDiagnostics` tool whenever it wants them.
--
-- Needs the `claude` CLI on PATH and nothing else -- the plugin is pure Lua on `vim.loop`,
-- so the npm bridge is gone from `install.sh` rather than replaced.
return {
	"coder/claudecode.nvim",

	-- Already installed and eager-loaded by `lua/plugin/ui.lua`; named here so lazy.nvim
	-- orders the two, not because it pulls in anything new. It is what backs the terminal
	-- window -- `provider = "auto"` below resolves to snacks when it is present.
	dependencies = { "folke/snacks.nvim", },

	-- Lazy-loading on `keys` alone would defer the plugin until a `<leader>a*` mapping is
	-- pressed, and until then `:ClaudeCode` would not exist -- so lazy.nvim gets the command
	-- list too, and creates stubs that load on first use.
	cmd = {
		"ClaudeCode",
		"ClaudeCodeFocus",
		"ClaudeCodeSelectModel",
		"ClaudeCodeAdd",
		"ClaudeCodeSend",
		"ClaudeCodeSendText",
		"ClaudeCodeTreeAdd",
		"ClaudeCodeStatus",
		"ClaudeCodeStart",
		"ClaudeCodeStop",
		"ClaudeCodeOpen",
		"ClaudeCodeClose",
		"ClaudeCodeDiffAccept",
		"ClaudeCodeDiffDeny",
		"ClaudeCodeCloseAllDiffs",
	},

	opts = {
		-- The one deviation from upstream defaults. A send is nearly always the first half
		-- of a sentence -- you hand Claude a selection in order to say something about it --
		-- and leaving focus in the source buffer means reaching for `<leader>af` every time.
		-- Only has an effect on the in-editor providers, which is what `auto` resolves to
		-- here; with `none`/`external` the terminal is outside Neovim and there is nothing
		-- to focus.
		focus_after_send = true,

		-- Everything else is left at its default on purpose, and the ones worth knowing are:
		-- `terminal.provider = "auto"` (snacks, given the dependency above),
		-- `terminal.split_side = "right"` at 30% width, `diff_opts.layout = "vertical"`,
		-- `auto_start = true` for the WebSocket server, and `track_selection = true`, which
		-- is what keeps Claude's view of the current file and selection live.
	},

	-- Upstream suggests `<leader>ac` to toggle and `<leader>aa` to accept a diff. Those two
	-- are swapped around here: `<leader>aa` has been the chat toggle and `<leader>ac` the
	-- send-context key since the agentic setup, and muscle memory is worth more than
	-- matching the README. `<leader>ar` keeps its meaning as well.
	--
	-- `<leader>an` is reused rather than retired -- it opened a new session under agentic,
	-- which has no equivalent here, and it pairs with `<leader>ay` as yes/no on a diff.
	--
	-- The `<leader>a` group label lives in `lua/plugin/keybinding.lua`.
	keys = {
		{
			"<leader>aa",
			"<cmd>ClaudeCode<cr>",
			mode = { "n", "v", },
			desc = "Claude: toggle terminal",
		},
		{
			"<leader>af",
			"<cmd>ClaudeCodeFocus<cr>",
			mode = { "n", "v", },
			desc = "Claude: focus terminal",
		},
		{
			-- Opens the CLI's own session picker. Under agentic this restored a session
			-- into Neovim; it is the same `claude --resume` either way, which is what makes
			-- a session started here resumable from a plain terminal and back again.
			"<leader>ar",
			"<cmd>ClaudeCode --resume<cr>",
			desc = "Claude: resume a session",
		},
		{
			"<leader>aC",
			"<cmd>ClaudeCode --continue<cr>",
			desc = "Claude: continue the last session",
		},
		{
			-- Restarts the CLI with `--model`. Not a mid-conversation switch -- see the
			-- header. `/model` inside the terminal is the live one.
			"<leader>am",
			"<cmd>ClaudeCodeSelectModel<cr>",
			desc = "Claude: select model",
		},
		{
			-- One key, two commands, because "add this to the context" is one intent: the
			-- whole buffer from normal mode, the selected range from visual. This is what
			-- `<leader>ac` did before.
			"<leader>ac",
			"<cmd>ClaudeCodeAdd %<cr>",
			desc = "Claude: add current buffer to context",
		},
		{
			"<leader>ac",
			"<cmd>ClaudeCodeSend<cr>",
			mode = "v",
			desc = "Claude: send selection to context",
		},
		{
			-- Filetype-scoped, so it only exists where there is a file under the cursor to
			-- add. `snacks_picker_list` covers both halves of this config's file UI: the
			-- explorer sidebar from `lua/plugin/explorer.lua` and a focused picker list from
			-- `lua/plugin/picker.lua`. The other names are upstream's, kept so the mapping
			-- still works if a different explorer is ever swapped in.
			"<leader>as",
			"<cmd>ClaudeCodeTreeAdd<cr>",
			ft   = { "snacks_picker_list", "NvimTree", "neo-tree", "oil", "minifiles", "netrw", },
			desc = "Claude: add file under cursor to context",
		},
		{
			-- `:w` and `:q` in the diff window do the same thing, and are what upstream
			-- documents. These are the explicit forms, for when the cursor is elsewhere.
			"<leader>ay",
			"<cmd>ClaudeCodeDiffAccept<cr>",
			desc = "Claude: accept diff",
		},
		{
			"<leader>an",
			"<cmd>ClaudeCodeDiffDeny<cr>",
			desc = "Claude: deny diff",
		},
	},
}
