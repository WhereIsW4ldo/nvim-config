-- PowerShell, which needs one setting to find its own server.
--
-- `powershell_es` has no fixed install location of its own -- upstream's `lsp/powershell_es.lua`
-- either takes an explicit `bundle_path` or falls back to asking `pwsh` to resolve the
-- `PowerShellEditorServices` module via `Get-Module -ListAvailable`, which only finds it if
-- it sits somewhere on `$env:PSModulePath`. Mason's `powershell-editor-services` package does
-- not add itself there: it installs into `~/.local/share/nvim/mason/packages/powershell-editor-services`,
-- a plain mason package directory, not a PSModulePath entry. Left unset, the fallback finds
-- nothing usable and the server fails to start at all -- verified, not theorised: the nearest
-- thing it did find was the package root itself, one level above the actual module, which
-- produced a `Start-EditorServices.ps1` path missing its `PowerShellEditorServices` segment and
-- "term ... is not recognized" from `pwsh`.
--
-- `bundle_path` sidesteps the lookup entirely -- it is the root mason already extracted the
-- module tree into, and upstream joins `bundle_path/PowerShellEditorServices/Start-EditorServices.ps1`
-- from it directly.
--
-- Every hook that would normally carry this is already spoken for. `neovim/nvim-lspconfig`
-- has both taken: `lsp.lua` owns `init`, `typescript.lua` owns `config` -- lazy.nvim merges
-- specs for one repo, but a function field is not merged, so a third `config` here would
-- have silently replaced typescript.lua's and broken Vue/TypeScript. `mason-lspconfig.nvim`
-- is no better: `lsp.lua` owns `opts` (which merges fine) but `terraform.lua` already owns
-- `init`.
--
-- `mason-org/mason.nvim` is the one plugin in the stack with nothing but `opts = {}` from
-- `lsp.lua` -- a table, which lazy.nvim merges across specs, not a function, so it does not
-- block this from adding its own `init`. `init` runs before the plugin loads rather than
-- after, but `vim.lsp.config` only has to win the race against the first `.ps1` buffer, and
-- mason.nvim loads eagerly at startup same as the rest of this stack.
return {
	"mason-org/mason.nvim",

	init = function()
		vim.lsp.config("powershell_es", {
			bundle_path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", "powershell-editor-services"),
		})
	end,
}
