-- Git porcelain: review changes, manage branches and worktrees.
--
-- A wrapper around the external `lazygit` TUI rather than a native Neovim UI. That is
-- the deliberate tradeoff: lazygit shows five panels at once (status, files, branches,
-- commits, stash) with the focused one highlighted and its keybindings listed along the
-- bottom, so it is always visible what acts on what. Neogit was tried first and lost on
-- exactly that -- being a Magit clone, everything hides behind single-letter popups.
--
-- Worktrees need lazygit >= 0.40.0, which added the Worktrees panel. `install.sh`
-- enforces that floor.
--
--   Inside lazygit:  <tab> / h l  cycle panels     ?  keybindings for the focused panel
--   Worktrees panel: n new   <space> switch   d remove
--   Branches panel:  n new   <space> checkout  d delete   w new worktree from branch
--
-- Costs of the wrapper, stated plainly: no native Neovim keymaps, autocommands or
-- statusline see the git state, and it needs the `lazygit` binary installed.
return {
	"kdheepak/lazygit.nvim",

	cmd = {
		"LazyGit",
		"LazyGitConfig",
		"LazyGitCurrentFile",
		"LazyGitFilter",
		"LazyGitFilterCurrentFile",
	},

	-- Upstream lists `plenary.nvim` under `dependencies`, but its own README calls it
	-- "optional for floating window border decoration". Omitted -- nothing else here
	-- needs plenary, and a border is not worth a dependency.

	-- Upstream suggests <leader>lg. Using <leader>g* to sit under the "Git" group that
	-- which-key already shows.
	keys = {
		{ "<leader>gg", "<Cmd>LazyGit<CR>",            desc = "Git: lazygit", },
		{ "<leader>gf", "<Cmd>LazyGitCurrentFile<CR>", desc = "Git: lazygit (current file's repo)", },
		{ "<leader>gl", "<Cmd>LazyGitFilter<CR>",      desc = "Git: commit log", },
	},
}
