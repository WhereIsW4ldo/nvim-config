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
--
-- These are PARSER names, not filetypes. The two vocabularies differ more often than is
-- comfortable -- `c_sharp` highlights the `cs` filetype, `tsx` highlights
-- `typescriptreact`, and `markdown_inline` has no filetype at all -- so the autocommand
-- below derives its pattern rather than reusing this list directly.
local languages = {
	"lua",

	-- Terraform. `hcl` is the base grammar, and stands on its own for the `.hcl` files
	-- that are not Terraform (Packer, Nomad, `docker-bake.hcl`).
	"hcl",
	"terraform",

	"c_sharp",

	-- Both ship with Neovim already; naming them keeps this list the honest answer to
	-- "what is supported", and makes `install()` a no-op rather than a silent gap.
	"markdown",
	"markdown_inline",

	"vue",

	-- TypeScript. `tsx` is a separate grammar, not a variant flag, and `jsdoc` is what
	-- both inject into comments.
	"javascript",
	"jsdoc",
	"tsx",
	"typescript",

	"dockerfile",

	"sql",

	"rust",

	-- Not requested on their own -- these are the file formats the languages above drag in.
	-- `css`/`html` are the `<style>` and `<template>` halves of a Vue SFC, `yaml` is
	-- Compose, `toml` is `Cargo.toml`, `json` is `tsconfig.json` and `package.json`.
	"css",
	"html",
	"json",
	"toml",
	"yaml",
}

-- Parser -> every filetype it highlights, from the registry core keeps. A parser with no
-- filetype of its own, like `markdown_inline`, yields just its own name -- harmless as an
-- autocommand pattern that nothing will ever match.
--
-- Only correct once nvim-treesitter has loaded: core itself knows about `help` and
-- `checkhealth` and nothing else, and every alias that matters here -- `cs`,
-- `typescriptreact`, `jsonc`, `terraform-vars` -- is registered by the plugin's own
-- `plugin/filetypes.lua`. Hence a function, called from `config`, which lazy.nvim runs
-- after sourcing that. Evaluated at spec scope it would return the bare parser names and
-- silently leave those four languages unhighlighted.
local function filetypes()
	local result = {}

	for _, language in ipairs(languages) do
		vim.list_extend(result, vim.treesitter.language.get_filetypes(language))
	end

	return result
end


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
			pattern = filetypes(),
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
