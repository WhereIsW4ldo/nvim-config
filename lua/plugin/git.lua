-- Git porcelain: review changes, manage branches and worktrees.
--
-- A Magit clone, replacing the `lazygit` TUI wrapper this file used to hold. That
-- wrapper's panels were plain terminal text -- no tree-sitter, no Neovim scrolling,
-- folds or search -- because they were lazygit's own screen, not a Neovim buffer.
-- Neogit's status, diff and log views are real Neovim buffers, so all of that works
-- for free, and `treesitter_diff_highlight` (on by default) highlights diff hunks with
-- the file's own syntax rather than plain +/- coloring.
--
-- Everything funnels through one buffer: `<leader>gg` opens status, and every other
-- action -- commit, log, branch, stash, push/pull, rebase, cherry-pick, worktree -- is
-- a single-letter popup from there (`c`, `l`, `b`, `Z`, `P`/`p`, `r`, `A`, `w`; `?` lists
-- them all). Nothing else needs its own top-level keymap.
--
-- Diffs are inline-only by design -- upstream calls this an explicit tradeoff and
-- offers `diffview.nvim` or `codediff.nvim` as an optional fuller diff viewer. Neither
-- is added here: the inline, tree-sitter-highlighted hunks already answer the
-- complaint about lazygit, and a second diff plugin is not worth the extra dependency
-- until inline is actually found lacking.
return {
	"NeogitOrg/neogit",

	dependencies = {
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
	},

	cmd = "Neogit",

	opts = {
		-- Upstream disables both by default, to keep the status buffer's own line
		-- prefixes (fold markers, section markers) uncluttered. `lua/config/vim.lua`
		-- turns both on globally for every other buffer, so leaving these at their
		-- default would make Neogit the one buffer in the editor without a gutter.
		disable_line_numbers          = false,
		disable_relative_line_numbers = false,
	},

	keys = {
		{ "<leader>gg", "<Cmd>Neogit<CR>",           desc = "Git: status", },
		{ "<leader>gf", "<Cmd>Neogit cwd=%:p:h<CR>", desc = "Git: status (current file's repo)", },
	},
}
