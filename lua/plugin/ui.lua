-- Floating replacements for Neovim's built-in `vim.ui.select` and `vim.ui.input`.
--
-- Both defaults render in the cmdline as a numbered `inputlist` prompt (see
-- `runtime/lua/vim/ui.lua`), which is still the case on 0.12. Overriding them here
-- fixes every caller at once -- `agentic.nvim`'s agent-mode and session pickers, LSP
-- code actions, `vim.lsp.buf.rename`, and anything else that goes through `vim.ui`.
--
-- Chosen over `stevearc/dressing.nvim`, which was the standard answer until it was
-- archived in Feb 2025; its README now points here explicitly. `fzf-lua` and
-- `mini.pick` were the other live candidates -- fzf-lua needs the `fzf` binary and
-- offers no `vim.ui.input`, mini.pick is thinner on picker sources.
--
-- Only the two `vim.ui` modules are switched on. snacks ships ~40 others (dashboard,
-- indent guides, scroll, statuscolumn, ...) and every one of them stays off until
-- it is asked for: upstream enables nothing that is not named in `opts`.
return {
	"folke/snacks.nvim",

	-- Not lazy-loadable. Setup is what installs the `vim.ui.*` overrides, so it has
	-- to have run before the first caller -- a `keys` or `event` trigger would leave
	-- an early prompt rendering in the cmdline. `priority` is upstream's advice for
	-- the same reason.
	lazy     = false,
	priority = 1000,

	--- @type snacks.Config
	opts = {
		picker = {
			enabled = true,

			-- The actual reason this plugin is here. Without it the picker is
			-- installed but `vim.ui.select` still falls through to the cmdline.
			ui_select = true,
		},

		input = { enabled = true, },
	},
}
