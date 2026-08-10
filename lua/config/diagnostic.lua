-- How diagnostics are presented. Core `vim.diagnostic` only -- no plugin is involved,
-- which is the whole reason this sits in `config/` rather than in a plugin spec.
--
-- It used to live in `plugin/diagnostic.lua`'s `init`, hung off the snacks spec, and it
-- silently stopped running. Four files now declare a `folke/snacks.nvim` spec, and
-- lazy.nvim merges duplicates field-by-field through `vim.merge`, whose `can_merge` only
-- merges tables (`lazy/core/util.lua:440`). An `init` is a function, so it falls to the
-- `ret = value` branch -- last spec wins, with no warning. Imports run alphabetically, so
-- `plugin/explorer.lua`'s `init` overwrote this one and none of it took effect.
--
-- `keys` survives that merge because lazy.nvim registers it per-fragment through its
-- lazy-load handler; `init` has no such treatment. Core options belong out here where
-- nothing can clobber them.
--
-- Required before `config.lazy`, so presentation is settled before any plugin loads.
vim.diagnostic.config({
	-- Both virtual handlers are off because `tiny-inline-diagnostic.nvim` draws the
	-- message itself. Upstream's README only tells you to disable `virtual_text`, but
	-- `virtual_lines` needs it too -- both handlers fire on the cursor line, so leaving
	-- either on renders the same message twice.
	virtual_text  = false,
	virtual_lines = false,

	-- The gutter symbol. This is what marks a line the cursor is not on, so it is
	-- load-bearing here rather than incidental, even though `true` is already the default.
	signs = true,

	-- Draws the squiggle. Also already the default -- but a flat one until the colorscheme
	-- asks for `undercurl`, which is what `plugin/colorscheme.lua` now does.
	underline = true,

	-- So an error outranks a warning for the single sign the gutter can show.
	severity_sort = true,
})
