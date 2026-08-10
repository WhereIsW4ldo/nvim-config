-- Notifications as floating toasts: `snacks.notifier`.
--
-- Costs no new plugin, the same way `lua/plugin/explorer.lua` does. `folke/snacks.nvim`
-- is already installed and eager-loaded by `lua/plugin/ui.lua`, and lazy.nvim merges the
-- `opts` of every spec naming the same repo -- so this file turns on a module that is
-- already paid for. `setup` is what reassigns the `vim.notify` global, and `ui.lua`
-- already pins `lazy = false` / `priority = 1000` for its own reasons, so the override is
-- in place before the first caller.
--
-- **What this does not do, stated plainly.** "Messages in the bottom left" is two
-- unrelated subsystems, and this only replaces one of them:
--
--   * `vim.notify(...)` -- what plugins call. LSP client errors, lazy.nvim's own output,
--     formatter and linter results. These become toasts. This is the large majority of
--     what is noisy in practice.
--   * Built-in Vim messages -- `:echo`, `:echomsg`, `"foo.lua" 12L, 340B written`,
--     `search hit BOTTOM, continuing at TOP`, `E486: Pattern not found`. These never go
--     through `vim.notify` at all; they are emitted on the separate `msg_show` UI event.
--     They stay in the cmdline, and no amount of notifier configuration will move them.
--
-- Only `folke/noice.nvim` moves that second group, by attaching to `vim.ui_attach` and
-- replacing the message, cmdline and popupmenu UI wholesale. Rejected for now on three
-- facts, not taste: it needs `nui.nvim` as a hard dependency, its own README still calls
-- it "highly experimental ... issues are to be expected" and recommends nightly with no
-- 0.12-specific retraction, and its default config runs ~200 lines plus a routes DSL.
-- Worth revisiting if the `written` / `search hit BOTTOM` line is what actually grates.
--
-- The other live candidates were all `vim.notify`-only, so none of them beat a module
-- that is already installed: `mini.notify` is the healthiest of them (last push
-- 2026-08-07, and it wires LSP progress with no autocommand) but duplicates a module this
-- config already has, and `vim.notify` is a single global slot with no chaining -- two
-- plugins assigning it means whichever `setup` runs last silently wins. `nvim-notify`
-- adds nothing over this and has the slowest cadence of the set (last push 2025-09-06).
-- `fidget.nvim` is LSP-progress-first and ships `override_vim_notify = false`.
-- `vigoux/notifier.nvim` is out on age alone -- no push since 2024-07-03.
--
-- Note for the record that snacks is in awesome-neovim only as `folke/snacks.nvim#picker`,
-- under Fuzzy Finder; the notifier module is not listed. Per CLAUDE.md that needs a stated
-- reason, and the reason is that it is already a dependency of this config.

-- Registered here in the module body rather than in the spec's `init`, which is not a
-- style choice -- `lua/plugin/explorer.lua` already defines `init` on this same repo, and
-- lazy.nvim does not merge that field. Fragments are chained by metatable and `init`
-- resolves to the nearest one, so a second definition shadows the first outright. Verified
-- against lazy.nvim directly: two fragments of one plugin each printing from `init` print
-- only the later file's line. Defining `init` here would silently delete the explorer's
-- quit-on-last-window handler. A module body runs at spec-import time during
-- `require("config.lazy")`, which for an eager plugin is the same startup pass `init`
-- would have got, and creating an autocommand needs nothing loaded.
local group = vim.api.nvim_create_augroup("waldo_notification", { clear = true, })

-- Neovim has no default display for LSP `$/progress` at all -- it is collected into
-- `vim.lsp.status()` and left for a statusline or a plugin to render, and nothing here
-- renders it. So this is not moving a message out of the cmdline; it is showing one that
-- was previously invisible. It is upstream's "Simple LSP Progress" recipe from
-- `docs/notifier.md`, unmodified.
--
-- The fixed `id` is the whole trick: re-notifying under an id already on screen updates
-- that toast in place instead of stacking a new one per progress report.
vim.api.nvim_create_autocmd("LspProgress", {
	group = group,
	desc  = "Show LSP progress as a notification",
	---@param ev {data: {client_id: integer, params: lsp.ProgressParams}}
	callback = function(ev)
		local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", }

		-- `vim.lsp.status()` drains the client's progress ring buffer as it reads it, so
		-- it has exactly one consumer by design. Nothing else in this config calls it --
		-- `mini.statusline` reports attached clients, not progress -- but a second caller
		-- added later would steal reports from this one, and the symptom would be a
		-- notification that stalls rather than an error.
		vim.notify(vim.lsp.status(), "info", {
			id    = "lsp_progress",
			title = "LSP Progress",

			-- A function, not a value: it is re-evaluated on every redraw, which is what
			-- animates the spinner between progress reports. Neovim carries the `begin`
			-- message's title over to `report` and `end`, so the final frame still has
			-- something to say next to the tick.
			opts = function(notif)
				notif.icon = ev.data.params.value.kind == "end" and " "
					or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
			end,
		})
	end,
})

return {
	"folke/snacks.nvim",

	-- Deliberately no `lazy` / `priority` here. `lua/plugin/ui.lua` already pins both,
	-- and repeating them in a second fragment only creates two places to disagree.

	--- @type snacks.Config
	opts = {
		-- Defaults are what is wanted, so only the flag that turns setup on is set. For
		-- the record, what is being accepted: `style = "compact"` (the border carries the
		-- icon and title, so a one-line message stays one line), `top_down = true` and
		-- `margin.right = 1`, hence top-right; a 3s timeout; and `level = TRACE`, which
		-- shows everything -- history keeps every notification regardless of this.
		--
		-- The default icons are Nerd Font glyphs, which this config already requires for
		-- the statusline and the explorer, so they are not a new dependency.
		--
		-- Also default, and easy to misread as a bug: `keep` holds a notification open
		-- while the cmdline is active, so toasts do not expire mid-`:command`.
		notifier = { enabled = true, },
	},

	keys = {
		{
			-- Leaf mappings rather than a `<leader>n` group: there are two of them, and
			-- `<leader>e` already sets the precedent for a bare letter. Nothing to add to
			-- `lua/plugin/keybinding.lua`, which registers prefix groups only.
			"<leader>n",
			function() Snacks.notifier.show_history() end,
			desc = "Notification history",
		},
		{
			-- Worth having because a toast is not always transient: anything sent with
			-- `timeout = 0` stays until dismissed, and `keep` holds the rest open for as
			-- long as the cmdline is. No argument means every notification currently up.
			"<leader>N",
			function() Snacks.notifier.hide() end,
			desc = "Dismiss all notifications",
		},
	},
}
