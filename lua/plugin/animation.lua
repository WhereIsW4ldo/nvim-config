-- Motion animation: the viewport when it scrolls, and the cursor when it jumps.
--
-- Two plugins rather than one, and the split is deliberate. `mini.animate` is the only
-- candidate that covers both in a single `setup` -- and mini.nvim is already installed
-- here (`lua/plugin/statusline.lua`, `lua/plugin/diff.lua`), so it would have been free.
-- It lost on two documented facts, not on taste:
--
--   * Its own docs name this config's exact `mousescroll` value as a jitter case --
--     "can appear slower or can have visual jitter ... modify 'mousescroll'".
--     `lua/config/vim.lua` sets `ver:1` for unrelated reasons and should not have to
--     move for an animation plugin.
--   * Any centering mapping chained onto a motion (`nzvzz`, `<C-d>zz`) has to be
--     rewritten through `MiniAnimate.execute_after()`. That is a tax on every future
--     mapping, paid for a cursor effect that is one highlighted space -- far subtler
--     than the smear below.
--
-- `neoscroll.nvim` was the third scrolling candidate and the only one with a real
-- large-file escape hatch (it drops syntax and tree-sitter mid-scroll). It still lost:
-- it maps a fixed list that excludes `gg` and `G`, documents no mouse-wheel behaviour
-- at all, and its README lists "`<C-u>`, `<C-d>`, `<C-b>`, `<C-f>` mess up macros" as
-- a known issue. `cinnamon.nvim` (last push 2024-08-07), `niuiic/scroll.nvim`
-- (2024-05-24) and `SmoothCursor.nvim` (2024-09-18) are all more than a year stale.
-- `LuxVim/nvim-luxmotion`, listed under awesome-neovim's Animation section, 404s.
return {
	{
		-- Costs no new plugin, the same way `lua/plugin/notification.lua` does.
		-- `folke/snacks.nvim` is already installed and eager-loaded by `lua/plugin/ui.lua`,
		-- and lazy.nvim merges the `opts` of every spec naming the same repo.
		--
		-- `opts` is safe to add from a second file; `config` would not be. See the note in
		-- `lua/plugin/diff.lua` -- lazy.nvim's `Util.merge` overwrites a non-table value,
		-- so two specs each defining `config` means the alphabetically later file silently
		-- wins. Tables merge, functions clobber.
		"folke/snacks.nvim",

		--- @type snacks.Config
		opts = {
			-- Hooks `WinScrolled` / `CursorMoved` rather than installing mappings, which is
			-- the whole reason it beat neoscroll: `<C-d>`, `zz`, `gg`, `G`, the mouse wheel
			-- and a scroll triggered by some other plugin's jump are all covered without
			-- naming any of them.
			--
			-- Left at defaults otherwise. Worth knowing what those are rather than
			-- rediscovering them later:
			--
			--   * 200ms linear, dropping to a 50ms profile when scrolls repeat inside
			--     100ms -- so holding `<C-d>` or spinning the wheel does not queue up a
			--     backlog of slow animations.
			--   * The default `filter` already excludes `buftype == "terminal"`, which
			--     matters because `lua/plugin/terminal.lua` is a snacks terminal.
			--
			-- Kill switch is `vim.g.snacks_scroll = false` for this module alone, or
			-- `vim.g.snacks_animate = false` for every snacks animation at once.
			scroll = { enabled = true, },
		},
	},

	{
		-- The cursor half, and it has to be a separate plugin: `snacks.animate` is not a
		-- cursor animator despite the name. It is a pure easing/timer library -- ~45 easing
		-- functions and one shared timer -- that `snacks.scroll`, `snacks.indent` and
		-- `snacks.dim` consume. There is no cursor module in snacks at all.
		--
		-- Chosen over the other terminal-capable cursor animators because it is the only one
		-- that draws a real trail: `mini.animate` moves a single highlighted space, and
		-- `SmoothCursor.nvim` only places a sign-column glyph keyed to the line number, so
		-- neither shows horizontal motion. This draws the smear as `virt_text` extmarks in
		-- floating windows, which is what makes it work outside a GUI -- upstream's phrasing
		-- is "in all terminals".
		--
		-- The tradeoff, stated plainly because it is inherent and not a bug: the smear is a
		-- *second*, fake cursor painted over the buffer. Text under it is hidden while it
		-- passes, and upstream warns it is "likely not compatible with other plugins that
		-- modify the cursor".
		"sphamba/smear-cursor.nvim",

		-- Nothing to draw until a cursor has moved, and it hooks its own autocommands on
		-- setup, so there is no early-caller problem of the kind that pins `ui.lua` eager.
		event = "VeryLazy",

		opts = {
			-- Explicit even though it is the default, because this is the option that makes
			-- the plugin coexist with `snacks.scroll` above. Drawing in buffer space means
			-- the smear is anchored to the text while the viewport is animating underneath
			-- it, instead of being smeared a second time by the scroll itself.
			scroll_buffer_space = true,

			-- Floating windows where the "cursor" is a selection highlight rather than a
			-- position -- a smear chasing it reads as a glitch. Filetypes verified against
			-- the installed snacks source, not guessed: `picker/core/list.lua`,
			-- `picker/core/input.lua`, `terminal.lua` and `input.lua` set these.
			filetypes_disabled = {
				"snacks_picker_list",
				"snacks_picker_input",
				"snacks_terminal",
				"snacks_input",
			},

			-- Everything else is upstream's default, which already matches this setup:
			-- `vertical_bar_cursor` false and `vertical_bar_cursor_insert_mode` true line up
			-- with Neovim's stock `guicursor` (block in normal, `ver25` in insert), and
			-- `termguicolors` is on in `lua/config/vim.lua`, so the smooth 16-level gradient
			-- applies and the `cterm_cursor_colors` fallback is not needed.
			--
			-- Two knobs to reach for if it looks wrong rather than merely unfamiliar:
			--   * `legacy_computing_symbols_support = true` -- markedly less blocky, but
			--     only if the terminal font has the block-drawing symbols. Left false
			--     because that is a property of the font, not of this config.
			--   * `hide_target_hack = true` with `never_draw_over_target = true` -- for the
			--     documented case where the real cursor stays visible next to the smear.
		},
	},
}
