-- An in-editor terminal: `snacks.terminal`, toggled with <C-/> as a bordered float.
--
-- Costs no new plugin, on the same terms as `lua/plugin/explorer.lua`. `folke/snacks.nvim`
-- is already installed and eager-loaded by `lua/plugin/ui.lua`. Unlike the explorer, this
-- module contributes no `opts` fragment: what it configures is one window, and that has to
-- be passed per call rather than through setup -- see `win` below for why.
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

-- The terminal window. Passed at the call site instead of living in an `opts` fragment,
-- because `snacks.terminal.open` merges `position = cmd and "float" or "bottom"` *over*
-- `Snacks.config.styles.terminal` (`Snacks.win.resolve` in `snacks/win.lua`: later tables
-- win) and only under the `win` table handed to the call -- so a style fragment can set
-- everything here except the one field that matters.
local win = {
	-- A float, where this was a bottom split, and only because a border was wanted: Neovim
	-- refuses to draw one on anything else. `nvim_open_win` errors outright with "Conflict:
	-- 'border' not allowed with non-float window", and `winborder` is scoped to floats too,
	-- so "bordered split" is not a thing to be configured -- there is no version of it.
	--
	-- The cost, stated plainly, is that a float draws over the buffer rather than taking
	-- room from it: text under the terminal is hidden while it is open instead of being
	-- squeezed upward, and `:wincmd =` no longer has any say in its size. `<C-h/j/k/l>`
	-- from terminal mode (`config/keymap.lua`) still leaves it -- 0.12 resolves directional
	-- window motions out of a float, verified rather than assumed.
	position = "float",

	-- `true`, not "rounded". Snacks resolves `border = true` through `vim.o.winborder`
	-- (`M:border()`), so the style stays defined once in `config/vim.lua` for every float
	-- in the editor rather than being restated here and drifting from it.
	border   = true,

	-- Sized and placed where the split used to be: full editor width (`width = 0` means
	-- full size *minus* the border, so the border lands on the edge columns rather than
	-- overflowing) and 40% of the height -- snacks' own `split` default, kept deliberately.
	width    = 0,
	height   = 0.4,

	-- A negative `row` counts from the bottom of the parent, and snacks takes the parent
	-- height to be `vim.o.lines` (`M:parent_size()`) -- which includes the rows the global
	-- statusline (`laststatus = 3`) and the command line occupy. A plain `-1` therefore
	-- draws the bottom border straight over the statusline; offsetting by `cmdheight` plus
	-- that one statusline row stops it flush above instead, and keeps doing so if
	-- `cmdheight` ever changes.
	row      = function() return -1 - vim.o.cmdheight end,

	-- No dimming. `snacks.win`'s `float` style defaults to a 60% backdrop, which is right
	-- for a modal picker and wrong here: a terminal at the bottom is read against the code
	-- above it, and that code should stay at full contrast.
	backdrop = false,
}


-- Shared by both bindings below rather than written twice. `nil` for `cmd` is what selects
-- a shell over a one-off command, and is also what makes `vim.v.count1` meaningful: the
-- terminal id is a hash of `cmd`, `cwd`, `env` and the count, and `win` is deliberately not
-- part of it, so changing the window here does not orphan a running shell.
local function toggle()
	Snacks.terminal.toggle(nil, { win = win, })
end


return {
	"folke/snacks.nvim",

	-- No `lazy` / `priority` here, deliberately -- `lua/plugin/ui.lua` pins both, and a
	-- second fragment repeating them only creates two places to disagree.
	--
	-- No `opts` either, so for the record, what the rest of the defaults are: the `winbar`
	-- of `<id>: <b:term_title>` that splits carry is suppressed on floats, which have no
	-- room for it, so the count is no longer visible anywhere; `stack` likewise only means
	-- something for splits. The shell is `vim.o.shell` -- unset in `config/vim.lua`, so
	-- Neovim's own `$SHELL` default, zsh here. `:checkhealth snacks` probes that it is
	-- actually executable.
	keys = {
		{
			-- Upstream's own binding.
			--
			-- Terminal mode is in `mode` so that the same key closes the window again from
			-- inside it, without having to double-<Esc> out to normal mode first.
			"<C-/>",
			toggle,
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
			toggle,
			mode = { "n", "t", },
			desc = "Terminal (toggle, <C-/> on emulators that send 0x1F)",
		},
	},
}
