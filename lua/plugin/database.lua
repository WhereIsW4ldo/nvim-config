-- A SQL client inside the editor: `tpope/vim-dadbod`, with `vim-dadbod-ui` for the
-- connection drawer and `vim-dadbod-completion` as a schema-aware blink source.
--
-- The requirement that decided this was not "run a query" -- every candidate does that --
-- but "reach a local SQL Server in Docker *and* an Azure SQL database whose only
-- credentials are the ones `az login` already cached". The second half eliminated the rest
-- of the category on architecture rather than taste.
--
-- How the Azure half works, traced end to end rather than assumed. dadbod's SQL Server
-- adapter shells out to `sqlcmd` and passes the URL's `authentication` param through with
-- no allow-list of values (`autoload/db/adapter/sqlserver.vim`):
--
--     (has_authentication ? ['--authentication-method', url.params.authentication] : [])
--
-- Setting that param also suppresses both `-U` and `-E`, so no username is sent at all.
-- `sqlcmd` here is `microsoft/go-sqlcmd`, whose `--authentication-method` accepts
-- `ActiveDirectoryAzCli`; that value maps to `azidentity.NewAzureCLICredential`
-- (`microsoft/go-mssqldb/azuread/configuration.go`), which shells out to `az` for a token.
-- The whole chain is URL param -> sqlcmd flag -> AzureCLICredential -> `az`, so nothing in
-- this file fetches or refreshes a token, and none is ever written to disk.
--
-- The two connection strings this exists for, recorded here because neither is committed
-- (see "Connections" below):
--
--     sqlserver://sa:PASSWORD@localhost:1433/DB?trustServerCertificate=true
--     sqlserver://SERVER.database.windows.net/DB?authentication=ActiveDirectoryAzCli&encrypt=true
--
-- `trustServerCertificate=true` becomes `-C` and is not optional for the Docker one:
-- go-sqlcmd negotiates encryption by default and the container's certificate is self-signed.
--
-- Ruled out on facts:
--   * `kndndrj/nvim-dbee` -- the best UI in the field, with a genuinely paginated result
--     grid that dadbod has no answer to, and the most starred. Architecturally unable to do
--     the Azure half: `dbee/adapters/sqlserver.go` imports the plain `go-mssqldb` package
--     and calls `sql.Open("sqlserver", ...)`, while AAD token acquisition lives in that
--     module's `azuread` subpackage under the separate driver name `azuresql`, which dbee
--     never registers -- so a `fedauth=...` param is silently inert. Its `{{ exec }}`
--     templating can fetch a token but has nowhere to deliver it. Also no commits in the 12
--     months to 2026-08-20, a README that still says "Alpha Software", and an nvim-cmp-only
--     third-party completion source.
--   * `joryeugene/dadbod-grip.nvim` -- richer UI and actively developed, but its own README
--     scopes SQL Server as "read-only", and its adapter hardcodes the sqlcmd argv with no
--     `-C`, no `-N`, no `--authentication-method` and no override hook. That fails the Azure
--     half outright and most likely the Docker half too, on the self-signed certificate.
--   * `zongben/dbout.nvim` -- can probably reach Azure (raw ADO.NET string -> `tedious` ->
--     `DefaultAzureCredential` -> `AzureCliCredential`), but that path is inferred from the
--     Node driver rather than documented by the plugin, results render as JSON, it has no
--     completion of its own, and it pulls an npm tree including native modules.
--   * `zerochae/dbab.nvim` -- awesome-neovim links a repo that 404s, as does the owning
--     account. The similarly named repo that does exist supports no SQL Server at all.
--   * `neomongo.nvim` (MongoDB only) and `dadbod-vertica.nvim` (a Vertica adapter).
--
-- Not listed in awesome-neovim's `## Database` section, which CLAUDE.md requires be said out
-- loud: vim-dadbod and its UI appear there only inside another entry's description. The
-- absence is verified, and the reason for overriding it is the Azure requirement above.
--
-- What is given up, plainly: results are `sqlcmd`'s own text output in a scratch buffer, not
-- an interactive grid -- no paging, no sorting, no cell editing. That is the price of the
-- CLI-shelling architecture that makes the Azure auth work in the first place.
--
-- Maintenance, stated rather than glossed: `vim-dadbod` sees roughly one commit a year
-- (stable by design, no deprecation notice, 4.4k stars); `vim-dadbod-completion` has had no
-- commits since 2025-03-19. Neither is deprecated, and the completion plugin is a thin
-- source over dadbod's own introspection, so it rots slowly.
--
-- Connections. Nothing is hardcoded here on purpose -- the Docker URL carries a password.
-- `:DBUIAddConnection` writes to `g:db_ui_save_location`, which defaults to
-- `~/.local/share/db_ui`, outside this repository. `vim.g.dbs` and the `$DBUI_URL` env var
-- are the alternatives if a connection ever becomes safe to commit; the Azure one above has
-- no secret in it and would qualify.
--
-- External dependency: `sqlcmd`, recorded in `install.sh` and `README.md`. It must be
-- `microsoft/go-sqlcmd` and not the legacy ODBC `mssql-tools` binary -- only the Go rewrite
-- has `--authentication-method`, and the legacy one has no `--version` flag either, which is
-- what lets `install.sh --check` tell the two apart.
return {
	{
		"tpope/vim-dadbod",

		-- Pulled in by the two specs below and never loaded on its own. It defines `:DB`,
		-- which is worth knowing about for one-off queries but is not bound to anything here.
		lazy = true,

		-- lazy.nvim runs every `init` during startup regardless of when the plugin itself
		-- loads, which is exactly what these need: the environment has to be in place before
		-- the first `sqlcmd` is spawned, and that includes the introspection runs that happen
		-- before any query has been typed.
		--
		-- Scope, stated plainly: `vim.env` is Neovim's own environment, so every child
		-- process inherits this -- a `sqlcmd` run by hand in the built-in terminal included.
		-- That is consistent rather than surprising, but it is wider than this plugin.
		init = function()
			-- How `sqlcmd` formats a result set, set through the environment rather than
			-- through flags. dadbod's adapter builds a fixed argv, passes no formatting flags
			-- at all, and offers no hook to add any -- but go-sqlcmd reads its scripting
			-- variables from the environment first: `InitializeVariables(args.useEnvVars())`
			-- in `cmd/sqlcmd/sqlcmd.go`, where `useEnvVars()` is true unless `-X` is passed,
			-- which dadbod never does. So this needs neither a `$PATH` wrapper script nor a
			-- `g:db_adapter_sqlserver` override, which are the two answers the upstream issue
			-- threads settle on.
			--
			-- `SQLCMDMAXFIXEDTYPEWIDTH` is the one that matters, and it is not the obvious
			-- one. It governs *declared-width* types -- `char(n)`, `varchar(n)`,
			-- `nvarchar(n)` -- and defaults to 0, meaning unlimited: a `varchar(255)` column
			-- is padded to 255 characters whether or not a single row is that long. That is
			-- what makes untouched sqlcmd output unreadable.
			-- `SQLCMDMAXVARTYPEWIDTH` is the one whose name suggests it, and it is the lesser
			-- half: it covers only the `(max)` types plus `xml`/`text`/`image`, and already
			-- defaults to 256.
			vim.env.SQLCMDMAXFIXEDTYPEWIDTH = "30"
			vim.env.SQLCMDMAXVARTYPEWIDTH   = "100"

			-- A script `sqlcmd` runs before the query itself, every time. The variable is
			-- documented as "the first time sqlcmd runs", which here means every invocation:
			-- dadbod spawns a fresh process per query rather than holding a session open.
			--
			-- Kept in the repository rather than beside the connections in
			-- `~/.local/share/db_ui`, so a fresh machine has it and this never points at a
			-- file that is not there. Guarded anyway -- an unset variable is a better failure
			-- than one pointing at nothing.
			local preamble = vim.fs.joinpath(vim.fn.stdpath("config"), "sql", "preamble.sql")

			if vim.uv.fs_stat(preamble) then
				vim.env.SQLCMDINI = preamble
			end
		end,
	},

	{
		"kristijanhusak/vim-dadbod-ui",

		dependencies = { "tpope/vim-dadbod", },

		cmd = {
			"DBUI",
			"DBUIToggle",
			"DBUIClose",
			"DBUIAddConnection",
			"DBUIFindBuffer",
			"DBUIRenameBuffer",
			"DBUILastQueryInfo",
		},

		-- `init` rather than the `opts` this repo prefers, because there is nothing for `opts`
		-- to call: this is a Vimscript plugin configured entirely through `g:` variables, and
		-- `plugin/db_ui.vim` reads several of them at source time. lazy.nvim runs `init` before
		-- the plugin joins the runtimepath, which is the only hook early enough.
		init = function()
			-- Upstream defaults this to 1, which executes the whole buffer as a query on every
			-- write of an sql file. Off deliberately: one of the two connections this exists
			-- for is a live Azure database and `:w` is muscle memory. The plugin's own
			-- buffer-local `<leader>S` still executes on demand, over a visual selection if
			-- there is one.
			vim.g.db_ui_execute_on_save = 0

			-- Route DBUI's notifications through `vim.notify`, which
			-- `lua/plugin/notification.lua` has already pointed at snacks.notifier -- so its
			-- progress messages become the same toasts as everything else rather than cmdline
			-- echoes that the next redraw eats.
			vim.g.db_ui_use_nvim_notify = 1

			-- Drawer icons. Nerd fonts are already assumed by the statusline and the explorer,
			-- so this only stops DBUI from being the one component still drawing ASCII.
			vim.g.db_ui_use_nerd_fonts     = 1
			vim.g.db_ui_show_database_icon = 1

			-- Named and cleared, per CLAUDE.md, so re-sourcing does not stack handlers.
			local group = vim.api.nvim_create_augroup("waldo_dbui_quit", { clear = true, })

			-- What counts as furniture rather than content, and therefore cannot hold Neovim
			-- open by itself. `dbui` is the drawer, `dbout` the result buffer.
			--
			-- `snacks_*` is in here too, and deliberately: the file explorer runs the same
			-- check in `lua/plugin/explorer.lua`, and if this one did not recognise its
			-- sidebar the two would deadlock -- each would see the other's windows, conclude
			-- something editable was still open, and neither would quit. Being the superset
			-- is also what lets the explorer's copy stay untouched: a lone `dbout` window with
			-- no drawer is handled here rather than there. `snacks_terminal` is content, not
			-- furniture -- a running shell should keep Neovim alive.
			local function is_furniture(filetype)
				return filetype == "dbui"
					or filetype == "dbout"
					or (filetype:find("^snacks_") ~= nil and filetype ~= "snacks_terminal")
			end


			-- The drawer is an ordinary split carrying a `nofile` buffer, not a float, and one
			-- real split is all Neovim needs to stay running -- so `:q` on the last file leaves
			-- the drawer and any result buffer sitting there to be closed by hand. Same problem
			-- the explorer has, solved the same way, and `lua/plugin/explorer.lua` records why
			-- `QuitPre` is the wrong event to hang this on: it fires before the window is gone,
			-- so the check races the teardown. `WinClosed` plus a `schedule` waits instead.
			vim.api.nvim_create_autocmd("WinClosed", {
				group = group,
				desc  = "Quit when the database drawer is all that is left",
				callback = function()
					vim.schedule(function()
						local open = false

						for _, win in ipairs(vim.api.nvim_list_wins()) do
							local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
							if filetype == "dbui" or filetype == "dbout" then
								open = true
								break
							end
						end

						if not open then
							return
						end

						-- Floats are skipped on purpose: they cannot hold Neovim open by
						-- themselves, so they never make the difference here.
						for _, win in ipairs(vim.api.nvim_list_wins()) do
							local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
							if vim.api.nvim_win_get_config(win).relative == ""
								and not is_furniture(filetype) then
								return
							end
						end

						-- `quitall` rather than `quitall!`, so a modified hidden buffer still
						-- stops the exit and says so. It throws rather than returning a status,
						-- and an uncaught throw inside a scheduled callback buries the one line
						-- that matters under a Lua traceback -- so catch it and re-echo it the
						-- way `:qa` would have.
						local ok, err = pcall(vim.cmd, "quitall")
						if not ok then
							local message = tostring(err):match("E%d+:.*") or tostring(err)
							vim.api.nvim_echo({ { message, "ErrorMsg", }, }, true, {})
						end
					end)
				end,
			})
		end,

		-- `<leader>D` and not `<leader>d`, which `lua/plugin/diagnostic.lua` already owns.
		-- These are the drawer-level commands; the query-buffer mappings (`<leader>S` execute,
		-- `<leader>W` save query, `<leader>E` edit bind parameters, `<leader>R` toggle result
		-- layout) are upstream's, buffer-local, and left alone.
		keys = {
			{ "<leader>Dd", "<cmd>DBUIToggle<cr>",        desc = "Toggle the database drawer", },
			{ "<leader>Da", "<cmd>DBUIAddConnection<cr>", desc = "Add a database connection", },
			{ "<leader>Df", "<cmd>DBUIFindBuffer<cr>",    desc = "Find the query buffer", },
			{ "<leader>Dr", "<cmd>DBUIRenameBuffer<cr>",  desc = "Rename the query buffer", },
			{ "<leader>Dq", "<cmd>DBUILastQueryInfo<cr>", desc = "Info on the last query", },
		},
	},

	{
		"kristijanhusak/vim-dadbod-completion",

		dependencies = { "tpope/vim-dadbod", },

		-- `sql` is what dadbod-ui gives its query buffers; the other two are dialects the
		-- source also understands. Loading on filetype is early enough for the blink provider
		-- below, which only resolves its module on the first completion request.
		ft = { "sql", "mysql", "plsql", },
	},

	{
		"saghen/blink.cmp",

		-- An `opts` fragment only. `lua/plugin/completion.lua` owns the engine, its keymap
		-- preset and the `config` that wires LSP capabilities; lazy.nvim merges the `opts` of
		-- every spec naming the same repo, which is what keeps this concern in this file
		-- instead of leaking a database detail into the completion one.
		opts = {
			sources = {
				-- A `per_filetype` list *replaces* `sources.default` rather than extending it,
				-- so `lsp` has to be repeated -- without it `sqls` would fall silent in exactly
				-- the buffers where SQL completion matters most. `path` is dropped in its
				-- place: there are no filesystem paths in a query.
				--
				-- Worth knowing about the division of labour here, since both sources answer
				-- for SQL: `sqls` only ever sees the Docker server, because it links the
				-- deprecated `denisenkom/go-mssqldb` and has no Entra token path at all. The
				-- dadbod source covers both connections, because it reuses dadbod's own
				-- introspection queries over the same `sqlcmd` invocation.
				per_filetype = {
					sql   = { "lsp", "dadbod", "snippets", "buffer", },
					mysql = { "lsp", "dadbod", "snippets", "buffer", },
					plsql = { "lsp", "dadbod", "snippets", "buffer", },
				},

				providers = {
					dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink", },
				},
			},
		},
	},
}
