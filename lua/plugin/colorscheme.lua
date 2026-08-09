-- Catppuccin, mocha flavour.
--
-- Chosen over `tokyonight.nvim` and `rose-pine/neovim`, the other two candidates whose
-- highlight groups actually cover this config: all three style snacks, which-key,
-- render-markdown and blink.cmp, but catppuccin is the only one with
-- `auto_integrations`, and it is the only one still under active development
-- (29 commits in the last six months, against 10 and 3).
--
-- `kanagawa.nvim` and `nightfox.nvim` were ruled out on facts rather than taste --
-- neither ships any `Snacks*` or `RenderMarkdown*` groups, so both plugins already
-- installed here would fall back to default highlights.
return {
	"catppuccin/nvim",

	-- The repo is `catppuccin/nvim`, so without this lazy.nvim installs it into a
	-- directory called `nvim`.
	name = "catppuccin",

	-- A colorscheme is the one thing that must not be deferred: anything drawn before
	-- it loads is drawn unstyled and then repaints.
	lazy     = false,
	priority = 1000,

	---@module "catppuccin"
	---@type CatppuccinOptions
	opts = {
		-- `auto` resolves through the `background` map below, so `:set background=light`
		-- switches to latte without any further wiring.
		flavour    = "auto",
		background = { light = "latte", dark = "mocha", },

		-- Reads lazy.nvim's plugin list and enables the matching highlight groups.
		-- Without it every integration is opt-in by name, which means editing this file
		-- each time a plugin is added -- exactly the coupling the per-concern layout
		-- exists to avoid.
		--
		-- One trap comes with it: detection runs at setup, but catppuccin serves the
		-- theme from a compiled cache under `stdpath("cache")/catppuccin`, and installing
		-- a plugin does not invalidate that cache. So a newly added plugin keeps its
		-- fallback highlights until the cache is rebuilt -- `:Catppuccin compile`, or
		-- delete the directory. Worth doing as the last step of adding any plugin
		-- catppuccin knows about.
		auto_integrations = true,
	},

	-- `setup` only builds and caches the palette; it does not apply it. A table alone
	-- cannot express the second step, which is why this is a `config` and not bare
	-- `opts`.
	config = function(_, opts)
		require("catppuccin").setup(opts)

		-- Deliberately NOT "catppuccin". Neovim 0.12 bundles its own
		-- `$VIMRUNTIME/colors/catppuccin.vim`, which is unrelated to this plugin and not
		-- maintained by the Catppuccin org; the plugin ships `catppuccin.lua` too, so
		-- that name resolves by runtimepath order and is ambiguous. `catppuccin-nvim` is
		-- upstream's disambiguated entry point and the one that honours `flavour`.
		vim.cmd.colorscheme "catppuccin-nvim"
	end,
}
