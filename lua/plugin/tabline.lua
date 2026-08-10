-- The tabline: `barbar.nvim`, showing open **buffers** as tabs.
--
-- The fork in this category is not which plugin but what a tab is. Neovim's native
-- tabpages are window layouts -- a handful of deliberately created workspaces -- and
-- `tabby.nvim` is the live plugin for making those look good. This config takes the other
-- model, the one most editors mean by "tabs": every buffer you open gets a tab, and the
-- line is a picture of the open files. `tabby.nvim` was rejected for that reason first,
-- and on facts second: 7 months stale, and it documents no diagnostics hook, no sidebar
-- offset and no pin/close-others commands -- everything is written by hand in a `line`
-- render function.
--
-- What decided it against the obvious pick: `bufferline.nvim` is the popular answer, and
-- it is stalled -- the last commit to `main` is 2025-01-14, 19 months ago, with 103 open
-- issues accumulating. It is not archived and carries no deprecation notice, which is
-- exactly why this is worth writing down: nothing about the repo announces it. Most of
-- the rest of the category is outright dead -- `nvim-tabline` (26 months),
-- `BufferTabs.nvim` (24), `tabline-framework.nvim` (41), `nvim-smartbufs` (43, and
-- self-labelled WIP).
--
-- That left `nvim-cokeline` and `mini.tabline`. cokeline is alive and the most flexible,
-- but every visual element is a per-buffer *function* rather than a table, which is the
-- opposite of this config's `opts`-over-`config` rule, and catppuccin has no integration
-- for it. `mini.tabline` costs literally nothing here -- `mini.nvim` is already loaded for
-- the statusline -- but upstream is explicit that it does not do custom buffer order,
-- pinning, diagnostics or a sidebar offset. It shows names and a modified marker. Those
-- four omissions are the whole reason this file names barbar instead.
--
-- The cost, stated plainly: barbar owns more behaviour than a display-only line does. It
-- keeps its own buffer order and its own close commands, so `:bdelete` and `:BufferClose`
-- are no longer the same operation -- prefer barbar's, since only it maintains the order.
return {
	"romgrk/barbar.nvim",

	-- Guarantees `mini.icons` is set up before the mock below runs. lazy.nvim merges every
	-- spec naming the same repo, so this is the same `mini.nvim` that `plugin/statusline.lua`
	-- configures -- naming it here only fixes the load order, it does not pull in a copy.
	dependencies = { "nvim-mini/mini.nvim", },

	-- Not lazy-loadable. The tabline is meant to be visible from the first buffer onward;
	-- deferring to `keys` would mean no tabs until a tab keymap was pressed, which defeats
	-- the point of having them.
	lazy = false,

	-- Upstream's own lazy.nvim snippet. barbar otherwise calls `setup` for itself on load,
	-- which would run once with defaults before `config` below ran with these options.
	init = function()
		vim.g.barbar_auto_setup = false
	end,

	opts = {
		icons = {
			diagnostics = {
				-- barbar's defaults are errors and hints on, warnings and info off, which is
				-- an odd split -- a warning is the severity most worth seeing from a tab you
				-- are not looking at. Warnings are on here and info stays off; info is the
				-- severity servers use for advisory chatter, and a tab has room for a count,
				-- not a nuance.
				--
				-- Hints are left at barbar's default of on. `tiny-inline-diagnostic.nvim`
				-- already surfaces them in the buffer, so turn this one off if the tabline
				-- starts feeling noisy.
				--
				-- Glyphs are set explicitly because barbar's stock error icon is a mis-encoded
				-- ligature (`ﬀ`) rather than a Nerd Font symbol. Assumes the terminal font
				-- carries the Nerd Font range, as the statusline already does.
				[vim.diagnostic.severity.ERROR] = { enabled = true,  icon = " ", },
				[vim.diagnostic.severity.WARN]  = { enabled = true,  icon = " ", },
				[vim.diagnostic.severity.INFO]  = { enabled = false, },
				[vim.diagnostic.severity.HINT]  = { enabled = true,  icon = " ", },
			},

			-- Dead weight in this config, so it is switched off rather than left to fail
			-- quietly: barbar reads git status from `gitsigns.nvim`, and `plugin/diff.lua`
			-- runs `mini.diff` instead. There is no `mini.diff` path upstream, so these
			-- counters would never render whatever their setting.
			gitsigns = {
				added   = { enabled = false, },
				changed = { enabled = false, },
				deleted = { enabled = false, },
			},
		},

		-- Offsets the tabline so it does not sit over the file-explorer sidebar.
		-- `snacks_picker_list` is the filetype snacks gives the list window
		-- (`snacks.nvim/lua/snacks/picker/core/list.lua:81`), which is what `snacks.explorer`
		-- is built from.
		--
		-- Note this is the filetype of *every* snacks picker list, not just the explorer, so
		-- a floating picker may also trigger the offset. Needs an interactive check.
		sidebar_filetypes = {
			snacks_picker_list = { event = "BufWinLeave", text = "Explorer", },
		},

		-- A buffer closed from the middle of the row hands focus to its left neighbour
		-- rather than to whatever was previously alternate, so closing several in a row
		-- walks the tabline predictably instead of jumping around it.
		focus_on_close = "left",
	},

	-- `opts` cannot express this. barbar has no `mini.icons` integration and reads file
	-- icons solely from `nvim-web-devicons`, which this config does not install --
	-- `mini.icons` is the provider, set up in `plugin/statusline.lua`. Rather than add a
	-- second icon plugin for one consumer, `mock_nvim_web_devicons` registers mini's
	-- implementation under the module name barbar looks for. Without this line barbar
	-- silently shows no file icons at all.
	config = function(_, opts)
		require("mini.icons").mock_nvim_web_devicons()
		require("barbar").setup(opts)
	end,

	keys = {
		-- Cycling. `<S-h>`/`<S-l>` are unbound in stock Neovim and sit next to the `<C-hjkl>`
		-- window motions in `config/keymap.lua`, which keeps "move between windows" and
		-- "move between tabs" on the same two fingers.
		{ "<S-h>",      "<Cmd>BufferPrevious<CR>",                  desc = "Tab: previous", },
		{ "<S-l>",      "<Cmd>BufferNext<CR>",                      desc = "Tab: next", },

		-- Jump straight to a position. Upstream suggests `<A-1>`..`<A-9>`; `<leader>` is used
		-- instead because Alt is unreliable across terminals -- many send it as an Esc prefix,
		-- which collides with the `<Esc>` mapping in `config/keymap.lua`.
		{ "<leader>1",  "<Cmd>BufferGoto 1<CR>",                    desc = "Tab: go to 1", },
		{ "<leader>2",  "<Cmd>BufferGoto 2<CR>",                    desc = "Tab: go to 2", },
		{ "<leader>3",  "<Cmd>BufferGoto 3<CR>",                    desc = "Tab: go to 3", },
		{ "<leader>4",  "<Cmd>BufferGoto 4<CR>",                    desc = "Tab: go to 4", },
		{ "<leader>5",  "<Cmd>BufferGoto 5<CR>",                    desc = "Tab: go to 5", },
		{ "<leader>6",  "<Cmd>BufferGoto 6<CR>",                    desc = "Tab: go to 6", },
		{ "<leader>7",  "<Cmd>BufferGoto 7<CR>",                    desc = "Tab: go to 7", },
		{ "<leader>8",  "<Cmd>BufferGoto 8<CR>",                    desc = "Tab: go to 8", },
		{ "<leader>9",  "<Cmd>BufferGoto 9<CR>",                    desc = "Tab: go to 9", },
		{ "<leader>0",  "<Cmd>BufferLast<CR>",                      desc = "Tab: go to last", },

		-- Reordering, on the shifted digits that sit above the jump keys.
		{ "<leader>b<", "<Cmd>BufferMovePrevious<CR>",              desc = "Tab: move left", },
		{ "<leader>b>", "<Cmd>BufferMoveNext<CR>",                  desc = "Tab: move right", },

		-- Closing. `BufferClose` rather than `:bdelete` -- see the note at the top of the
		-- file; only barbar's own command keeps its ordering straight.
		{ "<leader>bc", "<Cmd>BufferClose<CR>",                     desc = "Tab: close", },
		{ "<leader>bo", "<Cmd>BufferCloseAllButCurrentOrPinned<CR>", desc = "Tab: close others", },

		-- Pinning exempts a buffer from "close others" above, which is what makes that
		-- command safe to reach for.
		{ "<leader>bp", "<Cmd>BufferPin<CR>",                       desc = "Tab: toggle pin", },

		-- Jump-to-buffer mode: shows a letter on each tab, press it to go there. Faster than
		-- counting positions once more than a handful of files are open.
		{ "<leader>bb", "<Cmd>BufferPick<CR>",                      desc = "Tab: pick", },
	},
}
