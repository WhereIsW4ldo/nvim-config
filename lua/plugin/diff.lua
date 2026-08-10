-- Git hunks inside the buffer: gutter marks, hunk motions, stage and reset.
--
-- `mini.diff`, which costs no download -- `mini.nvim` is already installed whole for
-- `lua/plugin/statusline.lua`, and its modules stay inert until their own `setup` runs.
-- Chosen over `gitsigns.nvim`, the fuller plugin, and `vgit.nvim`, which needs
-- `plenary.nvim` plus `nvim-web-devicons` and documents neither a hunk textobject nor
-- partial-hunk staging.
--
-- What mini.diff wins on: `]h` / `[h` are its own defaults and are mapped in
-- operator-pending mode too, and apply / reset are real `operatorfunc` operators, so `.`
-- repeats them. gitsigns needs the external `vim-repeat` plugin for that.
--
-- What it costs, stated plainly:
--   * No blame of any kind. gitsigns has both current-line virtual text and a full-file
--     blame split; this has neither, and nothing here replaces them.
--   * No `vimdiff` against the index. The overlay below is the nearest thing and it is a
--     different shape -- virtual text interleaved into this buffer, not a second window.
--   * It stages a hunk but cannot unstage one. Upstream calls unstaging an explicit
--     non-goal and says to use a full Git client, which here is `<leader>gg`.
--   * `reset` never invokes git. It rewrites the buffer text back to the reference text,
--     which for the default source is the index.
return {
	-- Adds to the spec in `lua/plugin/statusline.lua` rather than competing with it:
	-- lazy.nvim merges specs for the same plugin across import files.
	"nvim-mini/mini.nvim",

	-- `config` here would be a silent bug. lazy.nvim's `Util.merge` overwrites a
	-- non-table value instead of merging it, and `{ import = "plugin" }` walks this
	-- directory alphabetically -- so `statusline.lua`'s `config` lands second and would
	-- replace whatever this file defined, with no warning. `init` is a key neither of the
	-- two specs otherwise uses, the same dodge `lua/plugin/diagnostic.lua` uses to add to
	-- `lua/plugin/ui.lua`'s snacks spec.
	--
	-- `init` runs before mini.nvim is on the runtimepath, so the setup call has to wait
	-- for an event. `VeryLazy` fires after startup, by which point the bundle is loaded.
	-- Nothing is missed by arriving late: `MiniDiff.setup` walks every listed buffer and
	-- enables it, so the file named on the command line is picked up regardless.
	init = function()
		local group = vim.api.nvim_create_augroup("plugin_diff", { clear = true, })

		vim.api.nvim_create_autocmd("User", {
			group    = group,
			pattern  = "VeryLazy",
			desc     = "Set up mini.diff once mini.nvim is on the runtimepath",
			callback = function()
				require("mini.diff").setup({
					view = {
						-- Not the default. mini.diff picks `"number"` whenever `number` is
						-- set, and `lua/config/vim.lua` sets it -- that recolours the line
						-- number rather than drawing anything in the gutter.
						style = "sign",

						-- Default is `▒` for all three: a full shaded cell told apart only
						-- by colour. A thin bar reads as an edge marker instead of as
						-- content, and leaves the cell legible next to a diagnostic sign.
						signs = { add = "▎", change = "▎", delete = "▁", },
					},
				})

				-- Not in `keys` below, and deliberately. lazy.nvim only installs `keys`
				-- handlers for plugins it has not loaded yet (`handler/init.lua`:
				-- `if not plugin._.loaded`), and mini.nvim is `lazy = false` for the
				-- statusline -- so a `keys` entry on this spec is silently dropped.
				vim.keymap.set(
					"n",
					"<leader>go",
					function() require("mini.diff").toggle_overlay() end,
					{ desc = "Git: toggle diff overlay", }
				)
			end,
		})
	end,

	-- The hunk mappings -- `]h` `[h` `]H` `[H` for motion, `gh` / `gH` for apply and
	-- reset, `gh` again as the textobject -- are created by `setup` itself and already
	-- carry a `desc`, so they are deliberately not restated anywhere.
}
