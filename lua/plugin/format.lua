-- Formatting: which formatter owns each filetype, and format-on-save.
--
-- Two engines behind one entry point. A filetype gets a CLI formatter only where one
-- genuinely beats the language server; everything else falls through to whichever server
-- is attached, which is what `lsp_format = "fallback"` means. So Lua is formatted by
-- `lua_ls` -- the EmmyLua engine that reads `.editorconfig` and therefore already agrees
-- with this repo's own style -- and NOT by stylua, which would silently disagree. Same
-- shape for Terraform (`terraformls` shells out to `terraform fmt`), Rust
-- (`rust_analyzer` -> rustfmt), C#, SQL and Dockerfiles: nothing to list, they are the
-- fallback.
--
-- prettier is where the server loses. `marksman` implements no formatting at all, so
-- markdown would otherwise get nothing; and `vtsls` formats with tsserver's own
-- formatter, which is not prettier's style and ignores a project's `.prettierrc`. Naming
-- prettier for the web filetypes also defuses a core footgun -- `vim.lsp.buf.format`
-- loops over *every* attached client advertising formatting, and a Vue SFC has two
-- (`vue_ls` and `vtsls`), which would take turns rewriting the buffer.
--
-- `prettierd` is an external dependency and lives in `install.sh`'s NPM_DEPS.

-- `prettierd` is the same prettier behind a daemon, so it pays its startup cost once per
-- session instead of once per save. Plain `prettier` follows it as the fallback: conform
-- resolves both through `node_modules/.bin` first, so a project-local copy still works on
-- a machine without the daemon. `stop_after_first` is what makes that a fallback rather
-- than a second pass over the same buffer.
local prettier = { "prettierd", "prettier", stop_after_first = true, }

return {
	"stevearc/conform.nvim",

	-- `BufWritePre` is what arms format-on-save: lazy.nvim loads conform on the first
	-- write and replays the event, so conform's own `BufWritePre` handler still fires for
	-- that same save rather than starting from the second one.
	event = "BufWritePre",
	cmd   = "ConformInfo",

	keys = {
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
	opts = {
		-- Only filetypes that need a CLI formatter appear here. An absent filetype is not
		-- an omission -- it is the fallback to its language server. A filetype with
		-- neither is a silent no-op, not a warning, because conform only complains when
		-- formatters were configured and then turned out to be missing.
		formatters_by_ft = {
			markdown        = prettier,

			vue             = prettier,
			javascript      = prettier,
			javascriptreact = prettier,
			typescript      = prettier,
			typescriptreact = prettier,

			-- The file formats the languages above drag in: the `<style>` and
			-- `<template>` halves of a Vue SFC, and the config files beside them.
			css             = prettier,
			scss            = prettier,
			html            = prettier,
			json            = prettier,
			jsonc           = prettier,
			yaml            = prettier,
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
	init = function()
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
