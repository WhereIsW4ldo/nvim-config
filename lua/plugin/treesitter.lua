-- Tree-sitter parsers, highlighting and structural folding.
--
-- Neovim bundles parsers and queries for c, lua, markdown, markdown_inline, query, vim
-- and vimdoc, and `$VIMRUNTIME/ftplugin/lua.lua` already starts the highlighter and sets
-- `foldexpr` for Lua. This file generalises both to every other language, and adds the
-- half that ftplugin leaves out -- `foldmethod`, without which `foldexpr` is inert.
--
-- Parsers are compiled locally, so this needs the `tree-sitter` CLI (>= 0.26.1, from a
-- package manager and NOT npm) plus a C compiler. Both live in `install.sh`.

-- The single answer to "which languages does this config support". It drives both the
-- parser install and the autocommand pattern below, so adding a language is one edit
-- here -- plus its server in `lua/plugin/lsp.lua`.
local languages = {
	"lua",
}


return {
	"nvim-treesitter/nvim-treesitter",

	-- `main` is the repo default, but it is named anyway: `master` is frozen and its API
	-- is entirely different, so which branch this is matters more than most spec fields.
	branch = "main",

	-- Not deferrable. Parsers must be installable before the first file opens, and the
	-- FileType autocommand has to be registered before the first FileType fires.
	lazy = false,

	-- Parser revisions are pinned inside the plugin commit, so updating the plugin can
	-- leave a compiled parser stale. This recompiles them.
	build = ":TSUpdate",

	-- `setup()` is deliberately absent: upstream states it is not needed for default
	-- values, and the only option it takes is `install_dir`, whose default is correct.
	config = function()
		require("nvim-treesitter").install(languages)

		local group = vim.api.nvim_create_augroup("waldo_treesitter", { clear = true, })

		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			pattern = languages,
			desc = "Start tree-sitter highlighting and structural folding",
			callback = function()
				-- `install()` is asynchronous, so on a cold machine a buffer can open
				-- before its parser has finished compiling. Unwrapped, `start()` throws
				-- that at the user on their very first launch.
				if not pcall(vim.treesitter.start) then
					return
				end

				-- Window-local-to-buffer, the way the runtime ftplugins set it, so these
				-- do not leak into a window later showing a file with no parser.
				vim.wo[0][0].foldmethod = "expr"
				vim.wo[0][0].foldexpr   = "v:lua.vim.treesitter.foldexpr()"
			end,
		})
	end,
}
