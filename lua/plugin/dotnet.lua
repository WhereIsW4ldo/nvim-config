-- .NET: the language server, the test runner, and the `dotnet` CLI verbs.
--
-- This owns the whole C#/F# story, which is why it is the one language file here that is
-- bigger than a settings tweak. `lua/plugin/lsp.lua` deliberately does NOT list a C#
-- server any more -- see below.
--
-- ── Why this replaced mason's `roslyn_ls` ────────────────────────────────────────────
--
-- Both stand up the same engine: Microsoft.CodeAnalysis.LanguageServer, the server behind
-- the VS Code C# extension. The difference is everything around it.
--
-- mason installed the raw NuGet package and `vim.lsp.enable()`d it, which gave a server
-- and nothing else -- no test runner, no `dotnet run`, no launch profiles, no user
-- secrets, and Razor unsupported. easy-dotnet drives the same server through its own
-- `dotnet-easydotnet` sidecar (`dotnet-easydotnet roslyn start`), and gets three things
-- mason's copy could not:
--
--   * Roslynator's ~500 extra analysers and refactorings, bundled and enabled by default.
--   * Solution awareness. It walks up from the buffer for a `.sln`/`.slnx` before falling
--     back to the nearest `.csproj`, so cross-project go-to-definition works instead of
--     the single-project view mason's config produced.
--   * Razor and `.cshtml`, which README.md previously recorded as flatly unsupported.
--
-- The two MUST NOT both be enabled. `roslyn_ls` in mason-lspconfig's `ensure_installed` is
-- auto-enabled, and would attach a second Roslyn to every `cs` buffer -- duplicate
-- diagnostics, doubled completion, and two multi-hundred-megabyte server processes
-- indexing the same solution. Removing it from that list is half of this migration.
--
-- ── The one external binary ──────────────────────────────────────────────────────────
--
-- `dotnet-easydotnet`, the EasyDotnet .NET global tool. It is not optional and it is not
-- a Lua file: the RPC server behind the test runner, the workspace diagnostics, the NuGet
-- completion and the LSP launch all live in it. The plugin will `dotnet tool install -g
-- EasyDotnet` on first load if it is missing, but that only helps when `~/.dotnet/tools`
-- is on PATH -- otherwise it installs successfully and is then never found again. So it
-- is in `install.sh` (DOTNET_TOOL_DEPS) rather than left to the plugin, and `--check`
-- reports both the tool and the PATH entry.
--
-- `roslyn-language-server` itself is NOT listed anywhere: the sidecar downloads and
-- manages it. That is also why the mason exception in CLAUDE.md no longer covers C#.
return {
	{
		"GustavEikaas/easy-dotnet.nvim",

		-- plenary for `plenary.job` in the fallback picker and `plenary.async` in the
		-- telescope one; snacks because it is what `picker` below names, and naming it here
		-- is what guarantees it is loaded rather than merely installed.
		--
		-- nvim-dap is listed for a subtler reason. easy-dotnet registers the `coreclr`
		-- adapter and the `cs` launch configurations from inside its own `setup()`, behind a
		-- `pcall(require, "dap")` -- so with dap absent it silently registers nothing, and
		-- with dap merely *installed but not yet loaded* it would depend on lazy.nvim's
		-- module loader firing at exactly the right moment. Declaring it makes the order a
		-- fact: dap is loaded before this `setup()` runs, so the registration always happens.
		-- See `lua/plugin/debug.lua`, which owns the session keys and the UI.
		dependencies = {
			"nvim-lua/plenary.nvim",
			"folke/snacks.nvim",
			"mfussenegger/nvim-dap",
		},

		-- `xml` is in this list on purpose, and it is the only entry that is not obviously
		-- .NET: Neovim resolves `.csproj`, `.fsproj`, `.slnx` and `Directory.Packages.props`
		-- to `xml`, and those buffers are where the ProjX language server serves NuGet
		-- package-name and version completion, where `Dotnet outdated` draws its virtual
		-- text, and where the csproj mappings live. Opening an unrelated XML file therefore
		-- loads this plugin too -- which costs a `require` and nothing more, because
		-- `setup()`'s two eager steps (preloading Roslyn, discovering tests) both bail
		-- immediately when no solution is found, and ProjX's own `root_dir` returns nil for
		-- anything that is not a `.csproj`.
		--
		-- `solution` is Neovim's filetype for `.sln`; `razor` covers both `.razor` and
		-- `.cshtml`. Loading on FileType is early enough for the server: `vim.lsp.enable()`
		-- replays the event over already-open buffers, so the file that triggered the load
		-- still gets a client.
		ft = { "cs", "fsharp", "razor", "solution", "xml", },

		-- `:Dotnet` with no argument lists every verb. The keys below are the handful worth a
		-- mapping; the long tail (restore, clean, pack, push, EF migrations, `solution
		-- select`) is reachable there and does not need one.
		cmd = "Dotnet",

		-- `<leader>c` is a new group -- "C#/.NET". `<leader>d` is Diagnostics and `<leader>D`
		-- is Database, so the obvious letter was taken twice over. Declared in
		-- `lua/plugin/keybinding.lua` like every other prefix.
		--
		-- The two debug entries are the .NET *entry points* -- pick a project, build it, and
		-- launch it under the debugger. Once a session is running it is driven from
		-- `<leader>x` and the function keys in `lua/plugin/debug.lua`, which are
		-- language-agnostic and stay that way.
		keys = {
			{ "<leader>cr", "<cmd>Dotnet run<cr>",                     desc = "Run project", },
			{ "<leader>cR", "<cmd>Dotnet run profile<cr>",             desc = "Run project with launch profile", },
			{ "<leader>cd", "<cmd>Dotnet debug<cr>",                   desc = "Debug project", },
			{ "<leader>cD", "<cmd>Dotnet debug profile<cr>",           desc = "Debug project with launch profile", },
			{ "<leader>cw", "<cmd>Dotnet watch<cr>",                   desc = "Watch project", },
			{ "<leader>cb", "<cmd>Dotnet build solution quickfix<cr>", desc = "Build solution into quickfix", },
			{ "<leader>ct", "<cmd>Dotnet testrunner<cr>",              desc = "Toggle the test runner", },
			{ "<leader>ce", "<cmd>Dotnet diagnostic<cr>",              desc = "Workspace diagnostics", },
			{ "<leader>cp", "<cmd>Dotnet add package<cr>",             desc = "Add a NuGet package", },
			{ "<leader>co", "<cmd>Dotnet outdated<cr>",                desc = "Show outdated packages", },
			{ "<leader>cs", "<cmd>Dotnet secrets<cr>",                 desc = "Edit user secrets", },
			{ "<leader>cn", "<cmd>Dotnet new<cr>",                     desc = "New project from template", },

			-- The file counterpart to `cn`, and the older of the two ways to make one.
			-- `createfile` drives `dotnet new`'s *item* templates, which is where the kinds
			-- the Roslyn path does not offer live: `struct` above all -- EasyDotnet 3.4.21's
			-- picker is Enum/Record/Interface/Class and nothing else -- plus the API and MVC
			-- controllers, the Razor items, and the config files (`.editorconfig`,
			-- `global.json`, `nuget.config`, `Directory.Build.props`, `dotnet-tools.json`).
			--
			-- Upstream marks its Lua entry point `@deprecated` in favour of the explorer
			-- binding below, so this is the fallback rather than the default: reach for `A` in
			-- the explorer first, and come here when the template is not one of the four.
			--
			-- The directory has to be computed rather than passed as `%:h`. `:Dotnet` is
			-- `nargs = "?"` and splits its own argument string, so it never expands a `%` --
			-- the literal two characters would arrive as the output path. With no argument at
			-- all it falls back to `.`, the process cwd, which for a solution open at its root
			-- is the one directory a new class almost never belongs in.
			{
				"<leader>cf",
				function()
					local dir = vim.fn.expand("%:p:h")

					vim.cmd("Dotnet createfile " .. (dir ~= "" and dir or vim.fn.getcwd()))
				end,
				desc = "New file from template",
			},
		},

		-- Everything not listed here is upstream's default, and most of the defaults are
		-- already what this config wants -- `lsp.enabled`, Roslynator, the float test runner,
		-- the csproj mappings and Razor are all on out of the box.
		opts = {
			-- Auto-detection would land on snacks anyway (its priority is snacks -> fzf ->
			-- telescope -> basic), but naming it makes that a decision rather than a
			-- coincidence, and keeps the pickers consistent with the rest of this config.
			picker = "snacks",

			-- Inserted into a newly created `.cs` file. Upstream defaults to `block_scoped`,
			-- the braced form; every `dotnet new` template since .NET 6 emits the file-scoped
			-- one, so this matches what the SDK itself would have written. One word to revert.
			auto_bootstrap_namespace = {
				type = "file_scoped",
			},
		},

		-- Project files are `xml` buffers, and two things follow from that which have nothing
		-- to do with the plugin's own options.
		--
		-- The indentation first. `lua/config/vim.lua` deliberately sets no indent options at
		-- all, leaving them to Neovim's built-in EditorConfig support. That is right for every
		-- language whose projects state what they want, and wrong for `.csproj`: the
		-- `.editorconfig` a `dotnet new` solution ships has `[*] indent_size = 4` for C#'s
		-- sake and frequently no section for project files at all, so a csproj inherits four
		-- spaces where the SDK's own templates -- and every csproj Visual Studio has written
		-- -- use two.
		--
		-- Winning that fight is the whole trick, and it is not a matter of picking a later
		-- event: `BufRead` and `BufReadPost` are the *same* event, so the order is
		-- registration order -- and nvim's editorconfig hook lives in a runtime plugin, which
		-- is sourced after `init.lua` and therefore after this `init`. Whatever is set inline
		-- here is overwritten a moment later; verified, `shiftwidth` came back 4. `FileType`
		-- loses for the same reason. `vim.schedule` is what settles it: it defers to after
		-- every handler for the event has run, editorconfig's included.
		--
		-- Note that this deliberately overrides an explicit `.editorconfig` too, so it is a
		-- statement of preference and not just a default. The patterns keep it narrow -- an
		-- ordinary `.xml` gets whatever its repo says.
		--
		-- Then format-on-save, which is the same fact seen from the other side. ProjX
		-- advertises `documentFormattingProvider`, and `lua/plugin/format.lua` names no CLI
		-- formatter for `xml`, so `lsp_format = "fallback"` handed every csproj write to
		-- ProjX -- which does not merely re-indent: it strips the blank lines between
		-- `<ItemGroup>`s and respaces `<PackageReference ... />`, producing a diff on every
		-- save of a file nobody asked to have reformatted. `disable_autoformat` is conform's
		-- own buffer-level opt-out, the variable `:FormatDisable!` sets, so this costs nothing
		-- else: `<leader>F` still formats a csproj on demand, and `:FormatEnable` re-arms the
		-- buffer.
		init = function()
			local group = vim.api.nvim_create_augroup("waldo_dotnet_project_file", { clear = true, })

			vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost", }, {
				group    = group,
				pattern  = { "*.csproj", "*.fsproj", "*.vbproj", "*.props", "*.targets", "*.slnx", },
				desc     = "Two-space indent for .NET project files, and no format-on-save",
				callback = function(args)
					vim.b[args.buf].disable_autoformat = true

					vim.schedule(function()
						if not vim.api.nvim_buf_is_valid(args.buf) then
							return
						end

						vim.bo[args.buf].expandtab  = true
						vim.bo[args.buf].shiftwidth = 2
						vim.bo[args.buf].tabstop    = 2
					end)
				end,
			})
		end,
	},

	-- The explorer half of "new C# file". `create_item` is easy-dotnet's Roslyn-backed
	-- file creator: it asks for a kind (class, interface, record, enum) and a name, then
	-- has the sidecar generate the file with the namespace the *project* implies rather
	-- than the one the directory path suggests. It reads `auto_bootstrap_namespace.type`
	-- above, so the file-scoped choice made there applies here too.
	--
	-- It is deliberately not a `:Dotnet` verb -- there is no command for it, only the Lua
	-- API -- because the whole point is that the target directory comes from a file
	-- explorer's cursor. So the binding has to live wherever the explorer is, and the
	-- explorer is `snacks.explorer`; see `lua/plugin/explorer.lua`.
	--
	-- This fragment lives here rather than there on purpose. lazy.nvim merges every spec
	-- naming the same plugin, so a second `folke/snacks.nvim` table is a supported way to
	-- extend the explorer without `explorer.lua` having to know what .NET is. Keeping the
	-- .NET knowledge in the .NET file is the same rule the rest of this directory follows.
	--
	-- Only `opts` is set, never `config`: `explorer.lua` records why a `config` fragment
	-- anywhere would replace the `Snacks.setup()` that `lua/plugin/ui.lua` depends on.
	--
	-- `A` rather than `a`, because `a` is snacks' own `explorer_add` -- an ordinary
	-- touch/mkdir, still worth having for the files Roslyn has no template for.
	{
		"folke/snacks.nvim",

		---@type snacks.Config
		opts = {
			picker = {
				sources = {
					explorer = {
						win = {
							list = {
								keys = {
									["A"] = "explorer_add_dotnet",
								},
							},
						},

						actions = {
							-- `picker:dir()` is the directory of the item under the cursor, or
							-- its parent when that item is a file -- exactly the "create it next
							-- to this" behaviour wanted, and it falls back to the picker's cwd on
							-- an empty list. `require` is what loads easy-dotnet here: the plugin
							-- is `ft`-lazy and a `.cs` buffer need not be open yet, so lazy.nvim's
							-- module loader is doing the work -- which also runs `setup()`, and
							-- therefore the options `create_item` reads.
							explorer_add_dotnet = function(picker)
								require("easy-dotnet").create_item(picker:dir())
							end,
						},
					},
				},
			},
		},
	},
}

-- ── Not configured, and why ──────────────────────────────────────────────────────────
--
-- File watching. Roslyn learns about on-disk changes either from Neovim, via
-- `workspace/didChangeWatchedFiles`, or from its own in-process watcher. Neovim's is the
-- better half of that choice everywhere except Linux, where it is backed by inotify and
-- registers one instance per directory -- a large solution exhausts
-- `fs.inotify.max_user_instances` and the file descriptor limit, and watching stops
-- working entirely. easy-dotnet therefore defaults to the in-process watcher on Linux,
-- and this config leaves it there rather than shipping a `lsp/easy_dotnet.lua` whose
-- correctness depends on sysctl settings that are not in this repo. `:checkhealth
-- easy-dotnet` reports which side is watching. To switch, raise the limits
-- (`fs.inotify.max_user_instances=1024`, `fs.inotify.max_user_watches=524288`, `ulimit -n
-- 4096`) and advertise `capabilities.workspace.didChangeWatchedFiles.dynamicRegistration`
-- from `lsp/easy_dotnet.lua` -- that file is merged on top of these defaults.
--
-- Restart-on-branch-change. `lsp.restart_roslyn_on_branch_change` watches `.git/HEAD` and
-- stops and starts the Roslyn client for that root when it moves. It exists for exactly
-- the staleness the in-process watcher above can leave behind, and it is off here for the
-- same reason it is off upstream: it is blunt, and a restart of a server that has just
-- indexed a large solution is not free. Turn it on if a checkout ever leaves diagnostics
-- or completion describing the branch you left.
--
-- Server settings. Inlay hints, code lenses and import organisation are configured
-- through Roslyn's own `["csharp|inlay_hints"]`-style keys, which belong in
-- `lsp/easy_dotnet.lua` and not in `opts` above. Nothing needs them yet: `lua/plugin/
-- lsp.lua` already turns inlay hints on for any server that advertises them.
