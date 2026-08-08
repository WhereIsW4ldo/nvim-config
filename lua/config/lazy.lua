-- Bootstrap lazy.nvim. This block is taken verbatim from the upstream install docs
-- (`:help lazy.nvim`, installation section) -- resync it from there rather than
-- hand-editing, since the snippet has changed across versions.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local clone = { "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath, }
	local out = vim.fn.system(clone)

	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg", },
			{ out, "WarningMsg", },
			{ "\nPress any key to exit...", },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		-- Imports every module in `lua/plugin/`. Note: lazy.nvim raises "No specs
		-- found for module" if that directory is empty, so it must always hold at
		-- least one spec file.
		{ import = "plugin", },
	},

	-- Until a colorscheme is chosen, fall back to one that ships with Neovim so the
	-- install screen is not unstyled.
	install = { colorscheme = { "habamax", }, },

	-- No update nags. Checking for updates stays a deliberate `:Lazy check`.
	checker = { enabled = false, },
	change_detection = { notify = false, },

	-- Skip the luarocks/hererocks path entirely; nothing here needs rockspecs, and
	-- leaving it on produces health warnings on a machine without luarocks.
	rocks = { enabled = false, },
})
