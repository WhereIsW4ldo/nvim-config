-- PowerShell, which needs one setting to find its own server.
--
-- `powershell_es` has no fixed install location of its own -- upstream's `lsp/powershell_es.lua`
-- either takes an explicit `bundle_path` or falls back to asking `pwsh` to resolve the
-- `PowerShellEditorServices` module via `Get-Module -ListAvailable`, which only finds it if
-- it sits somewhere on `$env:PSModulePath`. Mason's `powershell-editor-services` package does
-- not add itself there: it installs into `~/.local/share/nvim/mason/packages/powershell-editor-services`,
-- a plain mason package directory, not a PSModulePath entry.
--
-- `bundle_path` has to be the directory that directly contains `Start-EditorServices.ps1` --
-- NOT the mason package root one level above it. The installed `nvim-lspconfig` builds the
-- launch command as `bundle_path .. '/Start-EditorServices.ps1'` plus `-BundledModulesPath
-- bundle_path`, verified by reading `lsp/powershell_es.lua` out of the actual plugin
-- checkout rather than off GitHub's `main` branch -- the two disagree here (`main` joins an
-- extra `PowerShellEditorServices` segment that the installed version does not).
--
-- mason-lspconfig ships its OWN default for this one server --
-- `mason-lspconfig/lsp/powershell_es.lua` sets `bundle_path` to the package root (the wrong,
-- one-level-too-shallow value above) and applies it itself during `automatic_enable`, which
-- runs inside its own `setup()`. That is why this cannot be an `init` on `mason-org/mason.nvim`
-- the way `terraform.lua` handles `terraformls`: `init` runs before `mason-lspconfig.nvim`
-- even loads, so mason-lspconfig's own default -- applied later, inside its `setup()` --
-- silently overwrote it. `terraformls` has no such default (there is no
-- `mason-lspconfig/lsp/terraformls.lua`), which is the whole reason that route works for
-- Terraform and not here -- verified against the actual installed plugin, not assumed from
-- symmetry with `terraform.lua`.
--
-- So this has to run strictly after mason-lspconfig's `setup()` returns, which means owning
-- `config` on `mason-lspconfig.nvim` rather than `init`. `lsp.lua` gives that plugin only
-- `opts` (merged automatically into a `require("mason-lspconfig").setup(opts)` call lazy.nvim
-- generates when no spec defines `config`), and `terraform.lua` takes `init`, leaving `config`
-- the one hook still free. Defining it here means lazy no longer auto-generates that setup
-- call, so it is replicated by hand before applying the override -- dropping it would silence
-- `ensure_installed` and `automatic_enable` entirely.
return {
	"mason-org/mason-lspconfig.nvim",

	config = function(_, opts)
		require("mason-lspconfig").setup(opts)

		vim.lsp.config("powershell_es", {
			bundle_path = vim.fs.joinpath(
				vim.fn.stdpath("data"),
				"mason", "packages", "powershell-editor-services", "PowerShellEditorServices"
			),
		})
	end,
}
