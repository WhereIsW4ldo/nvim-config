-- The file explorer: `snacks.explorer`, a sidebar tree over the filesystem.
--
-- Costs no new plugin. `folke/snacks.nvim` is already installed and eager-loaded by
-- `lua/plugin/ui.lua` for the `vim.ui.select` / `vim.ui.input` overrides, and lazy.nvim
-- merges the `opts` of every spec naming the same repo -- so this file adds one flag to
-- a plugin that is already paid for. The same was true of `mini.files`, the other
-- zero-cost candidate, since `mini.nvim` is loaded for the statusline.
--
-- The real fork in this category is not which plugin but which mental model: a pinned
-- sidebar tree (neo-tree, nvim-tree, this) versus the filesystem rendered as an editable
-- buffer that applies on `:w` (oil.nvim, mini.files). Both are defensible; a sidebar was
-- what was asked for. oil will never grow one -- its maintainer's FAQ answers "Can oil
-- display files as a tree view?" with "No. A tree view would require a completely
-- different methodology, necessitating a complete rewrite." mini.files frames the same
-- distinction as its headline difference from nvim-tree: column view, not tree view.
--
-- What decided it against the two dedicated trees: this is the only one of them with
-- native LSP-aware rename. `explorer_rename` and `explorer_move` both route through
-- `Snacks.rename.rename_file()`, which issues `workspace/willRenameFiles`, applies the
-- returned workspace edit, then notifies `didRenameFiles` -- so moving a file fixes the
-- imports that pointed at it. With TypeScript, Vue, Rust and C# servers configured in
-- `lua/plugin/lsp.lua`, that is the difference between a rename and a bug hunt.
-- neo-tree and nvim-tree have no native equivalent; both would need `Snacks.rename`
-- bolted onto a rename event, and neo-tree additionally drags in `plenary.nvim` and
-- `nui.nvim` and has no documented `mini.icons` path -- it `pcall`s `nvim-web-devicons`.
--
-- The cost, stated plainly: this is a `snacks.picker` source wearing tree furniture, not
-- a purpose-built tree widget. Navigation is picker-native (`<CR>`/`l`/`h`/`<BS>`) rather
-- than each tree's bespoke bindings, and there is no upstream guidance on behaviour in
-- very large directories -- nvim-tree is the only candidate that documents guardrails
-- there (`max_folder_discovery`, watcher whitelisting). What is bought back is that the
-- explorer *is* the picker: fuzzy filtering and `<leader>/` live-grep-in-directory come
-- with it, and this config has no fuzzy finder otherwise.
return {
	"folke/snacks.nvim",

	-- Deliberately no `lazy` / `priority` here. `lua/plugin/ui.lua` already pins both,
	-- and repeating them in a second fragment only creates two places to disagree.

	--- @type snacks.Config
	opts = {
		-- The module defaults are already what is wanted, so only the flag that turns
		-- setup on is set. For the record, what is being accepted: `layout.preset =
		-- "sidebar"` and `tree = true` (hence a tree down the left), `git_status` and
		-- `diagnostics` both on with no extra plugin, `follow_file` to track the current
		-- buffer, and `watch` for live refresh.
		--
		-- `replace_netrw` defaults true, which is belt-and-braces here: `config/vim.lua`
		-- already sets `loaded_netrw`, so the augroup snacks deletes never exists. What
		-- still earns its keep is the directory-buffer handler behind the same flag --
		-- it is what makes `nvim .` and `:e lua/` open the explorer.
		--
		-- `trash` also defaults true: deletes go to the system trash instead of being
		-- unrecoverable. See the note in `install.sh` about `gio` -- the fallback when no
		-- trash command exists is a permanent delete, silently.
		explorer = { enabled = true, },

		picker = {
			icons = {
				git = {
					-- Upstream's default here is a literal ASCII `?`, and it is the only
					-- one in the set that is -- `staged` is U+25CF ●, `modified` U+25CB ○,
					-- `added` U+F44D and `renamed` U+F061 are Nerd Font glyphs. A
					-- typewriter question mark next to those reads as a rendering failure
					-- rather than a status.
					--
					-- U+25CC ◌ finishes the pattern the circles already start: solid for
					-- staged, hollow for modified, dotted for a file git is not tracking
					-- yet. Geometric Shapes rather than Nerd Font, so unlike the glyphs
					-- around it this one does not depend on the patched font.
					untracked = "◌",
				},
			},
		},
	},

	-- `init` rather than `config`: lazy.nvim calls `require("snacks").setup(opts)` only
	-- when no fragment defines `config`, so defining one here would silently replace the
	-- setup that `lua/plugin/ui.lua` depends on. `init` adds to startup instead of
	-- replacing it, and registering an autocommand needs nothing loaded anyway.
	--
	-- This lives here and not in `config/autocommand.lua` because it is about one
	-- plugin's windows, which is the line that file draws.
	init = function()
		-- Named and cleared, per CLAUDE.md, so re-sourcing does not stack handlers.
		local group = vim.api.nvim_create_augroup("waldo_explorer_quit", { clear = true, })

		-- Leaving the explorer as the last window keeps Neovim open, and it is not
		-- obvious why: the sidebar looks like a floating overlay, but only the list and
		-- the prompt are floats. They sit on a `snacks_layout_box` window with
		-- `relative = ""` -- an ordinary split, and one real split is all Neovim needs to
		-- stay running. So `:q` on the last file leaves a sidebar that has to be closed
		-- by hand.
		--
		-- The obvious fix -- close the explorer from `QuitPre`, before the quit lands --
		-- does not work, and fails in a way worth recording so it is not retried:
		-- `Picker:close` defers the actual teardown into a `vim.schedule` callback, and
		-- the layout it then restores brings the window back. The quit runs first, the
		-- teardown second, and Neovim is left sitting on the buffer it just closed.
		--
		-- So this waits instead of racing: once a window has actually gone, if an
		-- explorer is open and nothing left on screen is editable, quit. `quitall`
		-- rather than `quitall!` deliberately -- a modified hidden buffer should still
		-- stop Neovim from exiting and say so.
		vim.api.nvim_create_autocmd("WinClosed", {
			group = group,
			desc  = "Quit when the file explorer is all that is left",
			callback = function()
				vim.schedule(function()
					if not _G.Snacks or #Snacks.picker.get({ source = "explorer", }) == 0 then
						return
					end

					-- Floats are ignored on purpose: they cannot hold Neovim open by
					-- themselves, so they never make the difference here.
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						local buf      = vim.api.nvim_win_get_buf(win)
						local filetype = vim.bo[buf].filetype

						-- `^snacks_` stands in for "the explorer's own furniture": the list
						-- and prompt floats, and the `snacks_layout_box` split underneath
						-- them. `snacks_terminal` matches that prefix too but is content,
						-- not furniture -- see `lua/plugin/terminal.lua` -- so it has to
						-- hold Neovim open like any other split. Otherwise closing the last
						-- file quits, and kills a shell that was still running.
						if vim.api.nvim_win_get_config(win).relative == ""
							and (not filetype:find("^snacks_") or filetype == "snacks_terminal") then
							return
						end
					end

					-- `quitall` throws rather than returning a status, and an uncaught
					-- throw inside a scheduled callback prints a Lua traceback over the
					-- one line that actually matters. Catch it and re-echo it the way
					-- `:qa` would have: `E37: No write since last change`.
					local ok, err = pcall(vim.cmd, "quitall")
					if not ok then
						local message = tostring(err):match("E%d+:.*") or tostring(err)
						vim.api.nvim_echo({ { message, "ErrorMsg", }, }, true, {})
					end
				end)
			end,
		})
	end,

	keys = {
		{
			"<leader>e",
			function() Snacks.explorer() end,
			desc = "File explorer",
		},
	},
}
