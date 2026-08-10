-- Linting: external linters run over the buffer, reported as diagnostics.
--
-- The gap this fills is that a language server is not a linter. `lua_ls` type-checks but
-- never mentions an unused local; `vtsls` knows the type of every expression and nothing
-- about the project's ESLint rules; `marksman` resolves Markdown links and holds no
-- opinion on heading style. Those rules live in separate tools, and this runs them.
--
-- `nvim-lint` won over `none-ls.nvim`, `efm-langserver` and `ale` on architecture. It
-- spawns the linter, parses its output and calls `vim.diagnostic.set` directly -- no
-- in-memory LSP client (none-ls), no second server process needing per-tool `lint-formats`
-- wiring (efm-langserver), no Vimscript job control (ale). So nothing here can collide
-- with the real clients `lsp.lua` attaches. It also ships every linter below built in,
-- where none-ls has dropped `eslint`, `shellcheck` and `luacheck` from its core to
-- `none-ls-extras.nvim`, whose own tagline is "may be prone to break".
--
-- GitHub is a read-only MIRROR of https://codeberg.org/mfussenegger/nvim-lint, which is
-- where issues and PRs go. lazy.nvim installs from the mirror, which tracks upstream
-- commit for commit.
--
-- The linter binaries are NOT installed by lazy.nvim -- they live in `install.sh`, and
-- README.md records what each one is for. A linter that is not installed is skipped
-- silently (see the `filter` below); every other filetype keeps linting.
--
-- One security note, upstream's own: some linters prefer an executable relative to the
-- cwd over the one on `$PATH` -- `eslint_d` uses `./node_modules/.bin/eslint_d` when it
-- exists. That is what makes a project's own ESLint version and plugin resolution win,
-- and it is also arbitrary code from the repo you opened. Do not open an untrusted
-- repository with this enabled; upstream documents a `wrap_linter` sandbox recipe for
-- that case.
return {
	"mfussenegger/nvim-lint",

	-- `BufReadPre`, not `VeryLazy`: the autocommand below has to exist before
	-- `BufReadPost` fires, or the file Neovim was opened with is the one file that never
	-- gets linted.
	event = { "BufReadPre", "BufNewFile", },

	-- `config` rather than the `opts` CLAUDE.md prefers, and not because setup needs
	-- logic: `nvim-lint` has no `setup()` at all. It exposes `linters_by_ft` as a plain
	-- table and `try_lint()` as the trigger, so there is nothing for lazy.nvim to hand an
	-- `opts` table to.
	config = function()
		local lint = require("lint")

		-- FILETYPES -- a third vocabulary alongside the parser names and server names
		-- that `treesitter.lua` and `lsp.lua` warn about. A filetype absent here does
		-- not lint, which is also why `try_lint()` below needs no guard.
		--
		-- Two languages are deliberately absent because the server already covers them:
		-- C#, where `roslyn_ls` IS Roslyn -- the engine the standalone analysers call --
		-- and Rust, where `clippy` is a `rust_analyzer` setting rather than a separate
		-- process worth spawning alongside it.
		lint.linters_by_ft = {
			-- `lua_ls` reports types and syntax; luacheck reports unused locals, shadowed
			-- variables and global leaks, which it does not. Needs `.luacheckrc` to know
			-- `vim` exists -- this repo has one.
			lua             = { "luacheck", },

			-- Note that tflint is the one linter here that does NOT read the buffer:
			-- upstream's definition passes `--recursive` with `stdin = false`, so it
			-- lints the directory as it is on disk. Saving first is what makes it agree
			-- with what you are looking at.
			terraform       = { "tflint", },

			markdown        = { "markdownlint-cli2", },
			dockerfile      = { "hadolint", },

			-- Needs a dialect or it fails on every buffer -- sqlfluff defaults it to
			-- `None` and then requires one. Deliberately NOT passed as `--dialect` here:
			-- a CLI flag would outrank every project's own `.sqlfluff`. It is configured
			-- instead, `tsql` machine-wide with `postgres` per project -- see README.md.
			sql             = { "sqlfluff", },

			-- The one filetype here with no language server at all, so this is pure
			-- upside rather than an overlap. Neovim files shell scripts under `sh`
			-- regardless of the shell; shellcheck does not support zsh, so `zsh` is
			-- deliberately not mapped to it.
			sh              = { "shellcheck", },

			-- ESLint is architecturally separate from `vtsls` and `vue_ls`: they
			-- type-check, it enforces the project's own rules and plugin rules
			-- (`eslint-plugin-vue`) that they never see. `eslint_d` is the daemon form --
			-- identical rules, without paying Node startup on every lint.
			javascript      = { "eslint_d", },
			javascriptreact = { "eslint_d", },
			typescript      = { "eslint_d", },
			typescriptreact = { "eslint_d", },
			vue             = { "eslint_d", },
		}

		local group = vim.api.nvim_create_augroup("waldo_lint", { clear = true, })

		-- `nvim-lint` ships no trigger of its own, so this autocommand is the whole of it.
		--
		-- `InsertLeave` rather than `TextChanged`, which upstream also offers: the
		-- difference is one process per edit burst against one per keystroke, times every
		-- linter for the filetype. `BufReadPost` covers opening a file and `BufWritePost`
		-- the tools that only ever see what is on disk.
		vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave", }, {
			group    = group,
			desc     = "Run the linters registered for this filetype",
			callback = function()
				lint.try_lint(nil, {
					-- Skip linters whose binary is not on `$PATH`. Without this an
					-- uninstalled linter is a permanent nuisance rather than a one-off
					-- notice: upstream reports the `ENOENT` through plain `vim.notify`
					-- and not `notify_once`, so it would fire again on every save and
					-- every `InsertLeave` for the rest of the session.
					--
					-- Only "not installed" is silenced -- `./install.sh --check` is where
					-- that is meant to be visible. A linter that runs and then fails still
					-- reports itself.
					--
					-- `cmd` is resolved here because it is allowed to be a function and is
					-- not evaluated until later: `eslint_d` uses one to prefer a project's
					-- `./node_modules/.bin` copy, and that is the path that has to be
					-- tested, not the fallback name.
					filter = function(linter)
						local cmd = linter.cmd
						if type(cmd) == "function" then
							cmd = cmd()
						end

						return vim.fn.executable(cmd) == 1
					end,
				})
			end,
		})
	end,

	-- For the cases the autocommands do not cover: a linter you have just installed, or a
	-- tflint run after editing a sibling file it reads off disk.
	--
	-- Deliberately WITHOUT the filter above, so this is the loud counterpart to the quiet
	-- autocommand -- ask for a lint by hand and a missing binary says so instead of
	-- looking like a clean buffer.
	keys = {
		{
			"<leader>l",
			function() require("lint").try_lint() end,
			desc = "Lint buffer now",
		},
	},
}
