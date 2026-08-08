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

	-- `AgenticChat` is agentic.nvim's chat buffer. It sets that filetype and registers
	-- markdown as its treesitter language, so the parser side is already handled --
	-- but this plugin dispatches on `vim.bo.filetype`, so the filetype must be listed
	-- both here (to trigger loading) and in `file_types` below (to render).
	ft = { "markdown", "AgenticChat", },

	---@module "render-markdown"
	---@type render.md.UserConfig
	opts = {
		file_types = { "markdown", "AgenticChat", },
	},

	-- Concealing `**` and `` ` `` is done by Neovim's own markdown_inline highlight
	-- query (`(emphasis_delimiter) @conceal`), which only applies while the treesitter
	-- HIGHLIGHTER is running on the buffer. agentic.nvim deliberately skips it for the
	-- chat buffer -- see the `if name ~= "chat"` guard in its chat_widget.lua, commented
	-- "The chat buffer's highlighting is managed by MessageWriter".
	--
	-- The result is a split: render-markdown parses the buffer itself, so bullets and
	-- headings render, but emphasis markers stay visible. Starting the highlighter here
	-- restores the conceal. `init` (not `config`) so the autocommand exists before the
	-- chat buffer is ever created.
	init = function()
		local group = vim.api.nvim_create_augroup("waldo_markdown_conceal", { clear = true, })

		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			pattern = "AgenticChat",
			desc = "Start the treesitter highlighter so emphasis markers conceal",
			callback = function(args)
				pcall(vim.treesitter.start, args.buf, "markdown")
			end,
		})
	end,
}
