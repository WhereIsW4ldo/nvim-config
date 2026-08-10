-- Autocompletion and snippets: `blink.cmp`.
--
-- Chosen over `nvim-cmp` and `mini.completion`, the two other live options in
-- awesome-neovim's `Completion` section. `coq_nvim` is alive but its own README calls it a
-- hobby project with no version guarantees, and `compl.nvim` (51 stars) ships no snippet
-- library at all. Doing nothing was a real option too -- Neovim 0.12 has
-- `vim.lsp.completion` with `autotrigger` -- and it lost on snippets: core's `vim.snippet`
-- exposes only expand/jump/stop/active, with no loader for a snippet library, so every
-- snippet would have to be hand-written.
--
-- Against nvim-cmp: this is one plugin where that is six (engine, four sources, LuaSnip),
-- and hrsh7th's README states "This is my hobby project... don't expect a fix unless you
-- provide minimal configuration and steps to reproduce". Against mini.completion, which
-- would have cost nothing since mini.nvim is already vendored: its docs say plainly "What
-- it doesn't do: Many configurable sources" -- no path source, no cmdline menu, and
-- prefix-only matching with no frecency.
--
-- The cost, stated plainly: blink's V2 is mid-rewrite with breaking changes, so `version`
-- below pins the v1 line. Moving to V2 will be a deliberate migration, not a `:Lazy
-- update`.
return {
	"saghen/blink.cmp",

	-- The snippet library itself -- ~1,000 VSCode-format snippets. blink loads it
	-- automatically when present, so it needs no wiring beyond being installed.
	-- Project-local additions go in `~/.config/nvim/snippets/`, which the snippet source
	-- already searches.
	dependencies = { "rafamadriz/friendly-snippets", },

	-- A release tag, which is what makes lazy.nvim fetch the prebuilt Rust fuzzy matcher
	-- rather than needing a toolchain to build it. `1.*` and not `2.*` deliberately -- see
	-- the note above.
	version = "1.*",

	-- Not lazy-loadable, despite the obvious `event = "InsertEnter"`. The `config` below
	-- registers LSP capabilities, and that has to happen before the first client starts --
	-- deferring it to the first keystroke in insert mode means every server already
	-- attached was told the wrong thing.
	lazy = false,

	---@module "blink.cmp"
	---@type blink.cmp.Config
	opts = {
		-- Upstream's recommendation, and the one preset that takes no key Neovim already
		-- uses for something else: `<C-y>` accepts, `<C-n>`/`<C-p>` select, `<C-e>` hides,
		-- `<C-space>` opens the menu or its docs, `<C-b>`/`<C-f>` scroll the doc window.
		-- `<Tab>`/`<S-Tab>` jump between snippet placeholders and fall through to plain
		-- indent when no snippet is active.
		--
		-- `super-tab` (tab accepts) and `enter` are the alternatives.
		keymap = { preset = "default", },

		completion = {
			-- Upstream defaults this off. On, it costs a floating window on every selected
			-- item after `completion.documentation.auto_show_delay_ms` (500 by default);
			-- off, the same window is a `<C-space>` away.
			documentation = { auto_show = true, },

			menu = {
				draw = {
					components = {
						-- The kind glyphs come from mini.icons, already this config's icon
						-- provider for the statusline and the explorer. Without this blink
						-- draws its own built-in set, which is a second, slightly different
						-- vocabulary for the same LSP kinds.
						kind_icon = {
							text      = function(ctx)
								return (require("mini.icons").get("lsp", ctx.kind))
							end,
							highlight = function(ctx)
								local _, hl = require("mini.icons").get("lsp", ctx.kind)
								return hl
							end,
						},

						kind = {
							highlight = function(ctx)
								local _, hl = require("mini.icons").get("lsp", ctx.kind)
								return hl
							end,
						},
					},
				},
			},
		},

		-- Argument hints in a float while typing a call. Upstream marks this experimental
		-- and ships it off; it is on here because the alternative is core's `<C-s>`, which
		-- is a deliberate keypress rather than something that follows the cursor.
		--
		-- It claims `<C-k>` in insert mode, which is otherwise digraph entry. Set this to
		-- false to get that back.
		signature = { enabled = true, },

		-- Already the default. Spelled out because it is the whole answer to "where do
		-- completions come from", and because `opts_extend` below only means something if
		-- the list is declared here.
		sources = { default = { "lsp", "path", "snippets", "buffer", }, },
	},

	-- Makes a source added in some other spec append to the list above rather than replace
	-- it. Nothing does that yet; it is upstream's own recommendation and one line.
	opts_extend = { "sources.default", },

	-- `opts` cannot express the second half of this. blink advertises capabilities beyond
	-- core's defaults (label details, richer resolve support), and nothing wires them up on
	-- its own: `mason-lspconfig`'s `automatic_enable` calls `vim.lsp.enable()` with no
	-- knowledge of any completion plugin. The `"*"` applies it to every server, which is
	-- what keeps `lua/plugin/lsp.lua` free of any mention of this file.
	config = function(_, opts)
		local blink = require("blink.cmp")


		blink.setup(opts)

		vim.lsp.config("*", { capabilities = blink.get_lsp_capabilities(), })
	end,
}
