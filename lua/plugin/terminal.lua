-- An in-editor terminal: `snacks.terminal`, toggled with <C-/>.
--
-- Costs no new plugin, on the same terms as `lua/plugin/explorer.lua`. `folke/snacks.nvim`
-- is already installed and eager-loaded by `lua/plugin/ui.lua`. Unlike the explorer, this
-- module needs no configuration whatsoever, so this file adds no `opts` fragment at all --
-- it is keymaps and nothing else.
--
-- Worth recording, because it contradicts the pattern every other snacks fragment here
-- sets: there is no `terminal = { enabled = true, }` flag to find. `snacks.terminal.Config`
-- has exactly three fields (`win`, `shell`, `override`), and the module is reached on
-- demand through the `Snacks` global rather than switched on during setup the way `picker`,
-- `input` and `explorer` are.
--
-- The real fork in this category is what "a terminal" means. A shell to toggle in and out
-- of is one thing; a managed set of named terminals to send buffer lines into for REPL work
-- is another. This is the first. The second was `akinsho/toggleterm.nvim`, the standing
-- answer for years, and it is out on a fact: last push 2025-03-09, with 91 open issues.
-- Its maintained fork `waiting-for-dev/ergoterm.nvim` -- 1.2.0, API stabilised at 1.0.0,
-- no hard dependencies -- does cover the second model, and is the thing to reach for if
-- `term:send()` REPL workflows, `:TermSelect` switching, tab layouts or a `git_dir` cwd
-- ever become the requirement. `numToStr/FTerm.nvim` (2023-10-19) and `kassio/neoterm`
-- ("in low maintenance mode", its own README) were the other well-known names, both stale.
--
-- What is given up by staying with snacks, stated plainly: no send-to-terminal API of any
-- kind, so no REPL workflow; terminals are keyed by a hash of `cmd`, `cwd`, `env` and
-- `v:count1`, so `3<C-/>` does reach a third terminal but none of them can be named or
-- listed in a picker; no `tab` layout, only float and the four edges; and `cwd` is plain
-- `getcwd(0)` with no git-root derivation.
--
-- What is bought back, and why this is enough for a shell: the process survives being
-- toggled shut -- `hide()` closes the window and keeps the buffer -- double-<Esc> leaves
-- terminal mode, `q` hides, `gf` opens the file under the cursor, insert mode starts on
-- entry, and the window closes itself when the shell exits. Except on a non-zero exit
-- code: that is reported through `Snacks.notify.error` and the window is deliberately left
-- open so the error is still on screen to read.
return {
	"folke/snacks.nvim",

	-- No `lazy` / `priority` here, deliberately -- `lua/plugin/ui.lua` pins both, and a
	-- second fragment repeating them only creates two places to disagree.
	--
	-- No `opts` either, so for the record, what the defaults are: splits carry a `winbar`
	-- of `<id>: <b:term_title>` (suppressed on floats, which have no room for it), splits
	-- sharing a position stack rather than replace one another, and the shell is
	-- `vim.o.shell` -- unset in `config/vim.lua`, so Neovim's own `$SHELL` default, zsh
	-- here. `:checkhealth snacks` probes that it is actually executable.
	keys = {
		{
			-- Upstream's own binding. With no `cmd` argument the window opens as a bottom
			-- split rather than a float -- `position = cmd and "float" or "bottom"` in
			-- `snacks/terminal.lua` -- which is what is wanted for a shell: a float would
			-- cover the buffer it was opened over, and a split can be read alongside it.
			--
			-- Terminal mode is in `mode` so that the same key closes the window again from
			-- inside it, without having to double-<Esc> out to normal mode first.
			"<C-/>",
			function() Snacks.terminal.toggle() end,
			mode = { "n", "t", },
			desc = "Terminal (toggle)",
		},
		{
			-- Not a duplicate to tidy away. `/` and `_` share a control byte -- Ctrl with
			-- either transmits 0x1F -- so a good many terminal emulators send what Neovim
			-- reads as <C-_> when <C-/> is pressed, and a config bound only to <C-/> does
			-- nothing at all in those. Upstream ships both bindings for exactly this, and
			-- whichever one this terminal does not send is simply never triggered.
			"<C-_>",
			function() Snacks.terminal.toggle() end,
			mode = { "n", "t", },
			desc = "Terminal (toggle, <C-/> on emulators that send 0x1F)",
		},
	},
}
