-- The right-hand overview column: VSCode's minimap. A miniature rendering of the buffer,
-- carrying LSP diagnostics, git hunks, search matches and the cursor line.
--
-- This is the whole of that column. `dstein64/nvim-scrollview` -- a thin overview ruler --
-- was installed here first and then removed: with the map present the two stacked up, the
-- ruler even drawing its own bar inside the minimap window. The map subsumes what it did.
-- The one thing lost with it is marks, which the ruler showed and `mark.enabled` below
-- would restore.
--
-- What it actually draws, stated plainly: no terminal can render text smaller than one
-- cell, so nothing here is a literal preview of the code. Every minimap in the ecosystem
-- compresses several source lines and columns into a single cell and encodes the result
-- as braille -- eight dots per cell being the densest glyph family available. What makes
-- the result legible is not the dots but the *colour*: this plugin resolves the treesitter
-- highlights covering each codepoint and paints the braille with the one that occurs most
-- often, so a file reads as bands of comment green, string peach and keyword mauve. That
-- is the same cue the eye actually uses in VSCode, and it is the reason this replaced
-- `mini.map`, which is monochrome apart from its integration marks.
--
-- Not sourced from awesome-neovim. Its `Scrollbar` section has seven entries and none of
-- them does treesitter-coloured braille and is maintained. The three live thin rulers do
-- no syntax colouring at all and are not minimaps in the first place -- `nvim-scrollview`
-- was the best of them and is the one removed above; `satellite.nvim` states its
-- requirement as bare "Neovim nightly" and calls its own internals "fairly unideal and
-- unoptimised workarounds"; `nvim-scrollbar` has no mouse support and needs a second
-- plugin for search marks. `mini.map` is a real minimap but monochrome. That leaves
-- `codewindow.nvim`, which does colour its braille via treesitter and is the closest thing
-- to this -- ruled out on health, with no push since May 2025 and an open, unmerged report
-- that it throws `module 'nvim-treesitter.ts_utils' not found` against the current
-- treesitter rewrite.
-- The absence was verified rather than assumed: `neominimap` appears nowhere in the list.
-- Its own last commit is 2026-04-12, roughly four months old -- slower than `mini.nvim`,
-- comparable to `satellite.nvim`, and with no deprecation notice anywhere in the README.
--
-- Treesitter highlighting is optional upstream and silently degrades to plain braille
-- without it. `lua/plugin/treesitter.lua` already installs `nvim-treesitter`, so it is not
-- declared as a dependency here -- doing so would only force treesitter to load earlier.
return {
	"Isrothy/neominimap.nvim",

	-- Upstream's own installation snippet pins the major, and it means it: the v3 API
	-- moved `require("neominimap").on/off/toggle` to `require("neominimap.api")`, and the
	-- README still documents the old names as deprecated-but-present. `lazy-lock.json`
	-- pins the commit regardless; this decides what a deliberate `:Lazy update` accepts.
	version = "v3.x.x",

	-- Upstream annotates its own example with "NOTE: NO NEED to Lazy load". The minimap is
	-- meant to be on screen from the first buffer, and `auto_enable` below is what opens
	-- it, so there is no event worth waiting for.
	lazy = false,

	-- `opts` cannot express this. The plugin reads a single global, `vim.g.neominimap`,
	-- and has no `setup()` at all -- so the table has to be assigned, and assigned before
	-- the plugin loads, which is what `init` is for.
	init = function()
		--- @type Neominimap.UserConfig
		vim.g.neominimap = {
			-- Opens the minimap for every eligible buffer without further wiring. Already
			-- the upstream default, and named here because it is the whole reason the
			-- window appears at all -- `mini.map` shipped no equivalent and had to be
			-- opened by hand.
			auto_enable = true,

			-- The important deviation. Upstream defaults to `float`, which draws the map
			-- over the buffer -- that is what made `mini.map` cover ten columns of code.
			-- A split reserves real estate instead, the way VSCode does, so nothing is
			-- ever hidden behind it.
			--
			-- It also sidesteps a global setting. Upstream recommends `wrap = false` and
			-- `sidescrolloff = 36` alongside `float`, to stop the cursor wandering under
			-- the overlay -- and this config wraps by default, with `lua/config/keymap.lua`
			-- mapping `j`/`k` to `gj`/`gk` on the strength of it. Those two lines are
			-- recommended for `float` only, so `split` avoids the conflict entirely.
			layout      = "split",

			split       = {
				-- Otherwise a lone minimap in the last window keeps Neovim alive with
				-- nothing to edit.
				close_if_last_window = true,
			},

			-- The reason this plugin is here rather than `mini.map`, so named explicitly
			-- even though `true` is already the default. Turning it off leaves working
			-- but monochrome braille.
			treesitter  = { enabled = true, },

			-- Default is off. On, a click in the map jumps the source buffer to that line,
			-- which is the only mouse affordance left now that the ruler's clickable signs
			-- are gone.
			click       = { enabled = true, },

			-- Default is off. Worth the column: this is what shows *where* in the whole
			-- file the `/` matches are, not merely that the line under the cursor is one.
			search      = { enabled = true, },

			-- These two are a pair, and both defaults are wrong for this config. The `git`
			-- handler reads `gitsigns.nvim`, which is not installed; `lua/plugin/diff.lua`
			-- uses `mini.diff`, whose handler upstream ships disabled. Left at their
			-- defaults the map would simply show no hunks at all.
			git         = { enabled = false, },
			mini_diff   = { enabled = true, },
		}
	end,

	-- Upstream suggests a whole `<leader>n` namespace with sixteen entries across global,
	-- window, tab and buffer scopes. Two are enough here, and `<leader>m` is the more
	-- obvious prefix for a minimap -- `<leader>n` is unused either way, so this is a
	-- readability choice rather than a collision.
	keys = {
		{ "<leader>m", "<Cmd>Neominimap Toggle<CR>",      desc = "Minimap: toggle", },

		-- Focus moves the cursor into the map, where ordinary motions scrub the source
		-- buffer. The same command toggles back out.
		{ "<leader>M", "<Cmd>Neominimap ToggleFocus<CR>", desc = "Minimap: focus (browse)", },
	},
}
