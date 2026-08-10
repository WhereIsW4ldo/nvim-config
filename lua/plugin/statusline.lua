-- The status bar: `mini.statusline`, replacing the hand-written line this config carried
-- while no statusline plugin was installed.
--
-- Chosen over `lualine.nvim` and `slimline.nvim`, the only other candidates in
-- awesome-neovim's `Bars and Lines > Statusline` section still under development. Most of
-- that section is not: `heirline.nvim` has not been pushed since May 2025 and has no
-- commits in the last six months, `nougat.nvim` and `staline.nvim` are over two years
-- stale, `galaxyline.nvim` over four. `incline.nvim` is alive but draws floating
-- per-window labels, which is a different thing from a bar.
--
-- What decided it against lualine: catppuccin's `auto_integrations` reads lazy.nvim's
-- plugin list and matches on the repo name, and `mini.nvim` is in that map -- so the
-- `MiniStatusline*` groups get themed with no wiring here at all. lualine is absent from
-- the map and needs its `theme` set by hand. mini.nvim is also the most actively
-- developed of the three by a wide margin.
--
-- The cost, stated plainly: lualine's git sections are self-contained, and these are not
-- -- `section_git` and `section_diff` both read buffer variables that something else has
-- to populate. `mini.git` is set up below for the first. The second is fed by `mini.diff`,
-- which is a gutter decision rather than a statusline one and so lives in
-- `lua/plugin/diff.lua`; this file only renders whatever it publishes. Note that
-- `section_diff` reads `vim.b.minidiff_summary_string or vim.b.gitsigns_status`, so the
-- counts survive swapping mini.diff for gitsigns.
return {
	-- The whole bundle rather than the single-module `nvim-mini/mini.statusline` mirror.
	-- Modules are inert until their own `setup` runs, so the extra 40-odd cost nothing but
	-- disk -- and catppuccin's auto-integration matches the string "mini.nvim", which the
	-- mirror would not answer to.
	"nvim-mini/mini.nvim",

	-- Upstream's own recommendation, and it means `main` rather than the `stable` branch.
	-- `stable` only moves on releases; `lazy-lock.json` already pins the exact commit, so
	-- the branch choice only decides what a deliberate `:Lazy update` picks up.
	version = false,

	-- Not lazy-loadable. `setup` is what assigns `vim.o.statusline`, so deferring it would
	-- leave the built-in line drawn until whatever event fired.
	lazy = false,

	-- `opts` cannot express this: mini.nvim is a bundle with no top-level `setup`, so each
	-- module has to be required and set up by name.
	config = function()
		local statusline = require("mini.statusline")
		local claude     = require("config.claude-segment")

		-- Purely the data source for `section_git` above -- it tracks the branch and status
		-- into buffer-local variables. It also registers a `:Git` command, which is
		-- incidental here; `lua/plugin/git.lua` remains the git porcelain.
		require("mini.git").setup()

		-- `use_icons` is left at its default of true, which is what turns `Git`, `Diag` and
		-- `LSP` into single-cell glyphs. That is worth about ten columns, and those columns
		-- decide something: the Claude section below is the first thing truncation drops, so
		-- they are the difference between it surviving a vertical split and not.
		--
		-- `section_fileinfo`'s filetype icon is the one part that needs a provider. Without
		-- this line `ensure_get_icon` looks for `MiniIcons`, falls back to
		-- `nvim-web-devicons`, finds neither, and shows no icon at all -- silently, since a
		-- missing provider is not an error. mini.nvim is already installed, so it costs
		-- nothing but the call.
		--
		-- All of this assumes the terminal font carries the Nerd Font range.
		require("mini.icons").setup()

		statusline.setup({
			content = {
				active = function()
					local mode, mode_hl = statusline.section_mode({ trunc_width = 120, })
					local git           = statusline.section_git({ trunc_width = 40, })
					local diff          = statusline.section_diff({ trunc_width = 75, })
					local diagnostics   = statusline.section_diagnostics({ trunc_width = 75, })
					local lsp           = statusline.section_lsp({ trunc_width = 75, })
					local filename      = statusline.section_filename({ trunc_width = 140, })
					local fileinfo      = statusline.section_fileinfo({ trunc_width = 120, })
					local location      = statusline.section_location({ trunc_width = 75, })
					local search        = statusline.section_searchcount({ trunc_width = 75, })

					-- First thing dropped on a narrow window: it is the longest item on the
					-- line and the only one that is not about the buffer in front of you.
					local usage, usage_hl = "", nil
					if not statusline.is_truncated(120) then
						usage, usage_hl = claude.section()
					end

					return statusline.combine_groups({
						{ hl = mode_hl,                  strings = { mode, }, },
						{ hl = "MiniStatuslineDevinfo",  strings = { git, diff, diagnostics, lsp, }, },
						"%<", -- Truncate here first
						{ hl = "MiniStatuslineFilename", strings = { filename, }, },
						"%=", -- Right-align everything below
						{ hl = usage_hl,                 strings = { usage, }, },
						{ hl = "MiniStatuslineFileinfo", strings = { fileinfo, }, },
						{ hl = mode_hl,                  strings = { search, location, }, },
					})
				end,
			},
		})
	end,
}
