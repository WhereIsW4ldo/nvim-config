-- Formatting: which formatter owns each filetype, and format-on-save.
--
-- Two engines behind one entry point. A filetype gets a CLI formatter only where one
-- genuinely beats the language server; everything else falls through to whichever server
-- is attached, which is what `lsp_format = "fallback"` means. So Lua is formatted by
-- `lua_ls` -- the EmmyLua engine that reads `.editorconfig` and therefore already agrees
-- with this repo's own style -- and NOT by stylua, which would silently disagree. Same
-- shape for Rust (`rust_analyzer` -> rustfmt), C#, SQL and Dockerfiles: nothing to list,
-- they are the fallback.
--
-- prettier is where the server loses. `marksman` implements no formatting at all, so
-- markdown would otherwise get nothing; and `vtsls` formats with tsserver's own
-- formatter, which is not prettier's style and ignores a project's `.prettierrc`. Naming
-- prettier for the web filetypes also defuses a core footgun -- `vim.lsp.buf.format`
-- loops over *every* attached client advertising formatting, and a Vue SFC has two
-- (`vue_ls` and `vtsls`), which would take turns rewriting the buffer.
--
-- Terraform is the third case, and it is neither of those: the server formats correctly,
-- it just cannot be relied on to answer in time. `terraform-ls` handles RPC serially, and
-- it indexes every module under the workspace root -- which includes `.terraform/modules`,
-- the vendored copy of every module `terraform init` downloaded. In this machine's work
-- repos that is ~20k `.tf` files and 1.5 GB, so the request queue reaches 600+ entries and
-- single requests take up to 9s. A `textDocument/formatting` request lands behind that
-- backlog, conform's `timeout_ms` expires, Neovim sends `$/cancelRequest`, and the server
-- answers `[-32097] context canceled` -- surfacing as a `[LSP][terraformls] timeout`
-- notification on every save. Formatting itself was never slow: the server's own log says
-- `Finished 'terraform fmt' in 84ms`, and the bare CLI does it in 30ms.
--
-- Naming `terraform_fmt` here takes formatting off that queue entirely. It runs
-- `terraform fmt -no-color -` on the buffer over stdin -- the same `terraform fmt` the
-- server would have shelled out to, minus the server. The indexing cost is unavoidable and
-- still shows up in completion and hover latency; `indexing.ignoreDirectoryNames` is NOT a
-- way out, as `terraform-ls` rejects `.terraform` by name (`cannot ignore directory
-- ".terraform"`, error -32098) and refuses to initialise at all.
--
-- `terraform-vars` is the filetype for `.tfvars`, which is HCL and which the server would
-- also have formatted, so it needs the same treatment rather than being left on a fallback
-- that times out.
--
-- `prettierd` is an external dependency and lives in `install.sh`'s NPM_DEPS. `terraform`
-- is one too and lives in BREW_DEPS -- it was already required there for the server's sake,
-- and is now called directly.
local terraform_fmt = { "terraform_fmt", }

-- `prettierd` is the same prettier behind a daemon, so it pays its startup cost once per
-- session instead of once per save. Plain `prettier` follows it as the fallback: conform
-- resolves both through `node_modules/.bin` first, so a project-local copy still works on
-- a machine without the daemon. `stop_after_first` is what makes that a fallback rather
-- than a second pass over the same buffer.
local prettier = { "prettierd", "prettier", stop_after_first = true, }

-- SQL, which used to fall through to `sqls` and no longer can -- see `lua/plugin/lsp.lua`
-- for why that server was retired. sqlfluff was already installed as this config's SQL
-- linter, so formatting now comes from the same tool that judges the result. That is the
-- actual win: `sqls` formatted with tabs while sqlfluff's `tsql` rules demand four spaces,
-- so every formatted buffer used to come back with four fresh `LT02` warnings.
local sqlfluff = { "sqlfluff", }

return {
	"stevearc/conform.nvim",

	-- `BufWritePre` is what arms format-on-save: lazy.nvim loads conform on the first
	-- write and replays the event, so conform's own `BufWritePre` handler still fires for
	-- that same save rather than starting from the second one.
	event = "BufWritePre",
	cmd   = "ConformInfo",

	keys  = {
		{
			"<leader>F",
			function() require("conform").format({ async = true, }) end,

			-- Upstream suggests `<leader>f`; that is the Find group here. `mode = ""` is
			-- normal + visual + operator-pending, as `:map` gives. Visual is the point:
			-- conform defaults its range to the selection, so one key formats either the
			-- whole buffer or only what is highlighted -- and it synthesises the range
			-- from a minimal diff even for formatters that cannot do ranges themselves.
			mode = "",
			desc = "Format buffer",
		},
	},

	---@module "conform"
	---@type conform.setupOpts
	opts  = {
		-- Only filetypes that need a CLI formatter appear here. An absent filetype is not
		-- an omission -- it is the fallback to its language server. A filetype with
		-- neither is a silent no-op, not a warning, because conform only complains when
		-- formatters were configured and then turned out to be missing.
		formatters_by_ft = {
			markdown           = prettier,

			-- Not here for style -- see the header. This is the one entry whose reason is
			-- latency: the server's answer is correct and simply arrives too late.
			terraform          = terraform_fmt,
			["terraform-vars"] = terraform_fmt,

			-- Not a style preference either: with `sqls` gone there is no language server
			-- behind SQL at all, so this is the only thing that formats it.
			sql                = sqlfluff,

			vue                = prettier,
			javascript         = prettier,
			javascriptreact    = prettier,
			typescript         = prettier,
			typescriptreact    = prettier,

			-- The file formats the languages above drag in: the `<style>` and
			-- `<template>` halves of a Vue SFC, and the config files beside them.
			css                = prettier,
			scss               = prettier,
			html               = prettier,
			json               = prettier,
			jsonc              = prettier,
			yaml               = prettier,
		},

		-- Per-formatter overrides of conform's bundled definitions.
		formatters = {
			-- conform ships `sqlfluff` with `require_cwd = true`, so it runs only where a
			-- `.sqlfluff`, `pyproject.toml`, `setup.cfg`, `pep8.ini` or `tox.ini` sits above
			-- the file. Right for a project and wrong for the main SQL consumer here:
			-- `vim-dadbod-ui` writes its query buffers into a temp directory where no such
			-- root exists, so formatting a query would silently do nothing at all.
			--
			-- Turning it off does not lose project config -- sqlfluff still discovers a
			-- project's own `.sqlfluff` by walking up from the file it is given, and falls
			-- back to the machine-wide config that already pins the `tsql` dialect (see
			-- README.md). It only stops conform from refusing to run in the first place.
			--
			-- `exit_codes` is the other half, and without it this formatter is unusable in
			-- practice. `sqlfluff fix` exits 1 whenever any violation remains that it cannot
			-- fix, and conform treats a non-zero exit as a hard failure and throws the result
			-- away -- so the buffer is left unformatted and an error is logged. The rule that
			-- trips it constantly is `AM04`, "query produces an unknown number of result
			-- columns", which fires on `SELECT *` and is unfixable by definition: sqlfluff
			-- cannot know the columns. `SELECT *` is most of ad-hoc querying, and it is
			-- literally what `vim-dadbod-ui`'s own table helpers generate.
			--
			-- Accepting 1 is safe rather than merely convenient, verified both ways: every
			-- diagnostic sqlfluff emits goes to *stderr*, and stdout is always SQL -- the
			-- reformatted text when it could fix anything, and the input unchanged when the
			-- buffer does not parse at all. So the worst case is a buffer left exactly as it
			-- was. conform's own bundled `standardrb` and `puppet-lint` definitions do the
			-- same thing for the same reason.
			sqlfluff = { require_cwd = false, exit_codes = { 0, 1, }, },
		},

		-- Applies to `conform.format()` and to format-on-save alike, so the fallback rule
		-- is stated once and cannot drift between the keymap and the autocommand.
		default_format_opts = {
			lsp_format = "fallback",
		},

		-- A function rather than a table purely so the disable flags below can be read.
		format_on_save = function(bufnr)
			if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
				return
			end

			-- Above conform's 1000 default, because the first save of a session is where
			-- `prettierd` starts its daemon; subsequent saves are milliseconds. This
			-- blocks the write, so treat it as a ceiling for the pathological case and
			-- not as a budget.
			return { timeout_ms = 2000, }
		end,
	},

	-- Commands, not keymaps, and in `init` rather than `config`: both only set the
	-- variable that `format_on_save` reads, so they should work before conform has ever
	-- been loaded -- including in a session where nothing has been written yet.
	init  = function()
		vim.api.nvim_create_user_command("FormatDisable", function(args)
			if args.bang then
				vim.b.disable_autoformat = true
			else
				vim.g.disable_autoformat = true
			end
		end, {
			bang = true,
			desc = "Disable format-on-save (! for this buffer only)",
		})

		vim.api.nvim_create_user_command("FormatEnable", function()
			vim.b.disable_autoformat = false
			vim.g.disable_autoformat = false
		end, {
			desc = "Re-enable format-on-save",
		})
	end,
}
