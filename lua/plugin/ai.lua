-- Claude Code session management, over the Agent Client Protocol.
--
-- Sessions are interchangeable with the terminal `claude` CLI: the ACP provider owns
-- them, so a session started in Neovim can be resumed in the terminal and vice versa.
-- Multiple sessions run simultaneously and keep working while hidden -- closing a
-- window or tab does not stop the session behind it.
--
-- Requires the provider binary, which this plugin deliberately does not install:
--   npm i -g @agentclientprotocol/claude-agent-acp
-- Auth reuses the existing `claude /login` session; no API key is needed. See README.md
-- for version pinning and why upstream's pnpm / prebuilt-binary advice does not apply.
return {
	-- TEMPORARY FORK, not upstream. On every commit from `10f9bab` (2026-08-01)
	-- onward, restoring a session leaves it with no modes and no models:
	-- `_bootstrap_session` early-returns while `_is_restoring_session` is set, so the
	-- `session/new` whose response is the only source of that data is never sent.
	-- Switching mode then reports "This provider does not support mode switching",
	-- the header shows no mode, and the model picker is empty. Upstream has regressed
	-- this three times (issues #180, #277, and #310).
	--
	-- This branch is upstream `main` plus the one-line fix -- so unlike pinning to a
	-- pre-regression commit, #297's background sessions are kept. Revert this block
	-- to `"carlos-algms/agentic.nvim"` once PR #311 lands.
	--   issue: https://github.com/carlos-algms/agentic.nvim/issues/310
	--   PR:    https://github.com/carlos-algms/agentic.nvim/pull/311
	-- Background and the full trace: `docs/agentic-restore-modes.md`.
	"WhereIsW4ldo/agentic.nvim",
	branch = "fix/restore-config-options",

	--- @type agentic.PartialUserConfig
	opts = {
		provider = "claude-agent-acp",

		keymaps = {
			prompt = {
				-- Replaces the upstream default of `<C-s>`. Plain `<CR>` in normal mode
				-- is kept so Enter still submits without a modifier.
				--
				-- `<C-CR>` needs a terminal that can encode it -- see README.md, under
				-- "Terminal key support".
				submit = {
					"<CR>",
					{
						"<C-CR>",
						mode = { "n", "v", "i", },
					},
				},
			},
		},

		folding = {
			tool_calls = {
				-- Collapse every completed tool call, not just long ones. Upstream
				-- defaults to a 10-line threshold, which leaves short script and
				-- command output expanded; 0 folds all of them.
				--
				-- The header and completion status stay visible -- only the body is
				-- hidden. Expand with the usual fold keys: `za` toggles the one under
				-- the cursor, `zo`/`zc` open/close it, `zR`/`zM` do the whole buffer.
				threshold = 0,

				-- Left at the default deliberately: a tool call that FAILED stays
				-- expanded, so an error is never hidden behind a fold.
				fold_on_error = false,
			},
		},
	},

	-- Upstream suggests <C-\>, <C-'> and <C-,>. Using <leader>a* instead: <C-,> was
	-- the terminal toggle in the previous config, and control-punctuation chords are
	-- delivered inconsistently across terminal emulators.
	keys = {
		{
			"<leader>aa",
			function() require("agentic").toggle() end,
			mode = { "n", "v", },
			desc = "Agentic: toggle chat",
		},
		{
			"<leader>an",
			function() require("agentic").new_session() end,
			mode = { "n", "v", },
			desc = "Agentic: new session",
		},
		{
			"<leader>ar",
			function() require("agentic").restore_session() end,
			desc = "Agentic: restore session",
		},
		{
			"<leader>ac",
			function() require("agentic").add_selection_or_file_to_context() end,
			mode = { "n", "v", },
			desc = "Agentic: add file or selection to context",
		},
		{
			"<leader>ad",
			function() require("agentic").add_current_line_diagnostics() end,
			desc = "Agentic: add current line diagnostics",
		},
		{
			"<leader>aD",
			function() require("agentic").add_buffer_diagnostics() end,
			desc = "Agentic: add buffer diagnostics",
		},
	},
}
