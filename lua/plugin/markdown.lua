-- In-buffer markdown rendering: conceals the raw markup and draws headings, bullets,
-- checkboxes, code blocks and tables instead.
--
-- Treesitter highlighting alone only *colours* `#` and `**` -- it does not hide them.
-- This is what actually prettifies the text.
--
-- Note: upstream's example spec lists `nvim-treesitter` under `dependencies`, but only
-- as a convenience for installing parsers. It is deliberately omitted here -- the
-- plugin's own health check uses core `vim.treesitter.*` only, and Neovim 0.12 bundles
-- the `markdown` and `markdown_inline` parsers it needs.
return {
	"MeanderingProgrammer/render-markdown.nvim",

	-- Plain markdown files, and nothing else.
	ft = "markdown",

	---@module "render-markdown"
	---@type render.md.UserConfig
	opts = {},
}
