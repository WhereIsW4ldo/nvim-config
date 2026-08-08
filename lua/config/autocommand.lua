-- One named group, cleared on load, so re-sourcing this file replaces its handlers
-- instead of stacking a second copy of each.
local group = vim.api.nvim_create_augroup("waldo_autocommand", { clear = true, })

-- Briefly highlight yanked text, so it is obvious what was captured.
vim.api.nvim_create_autocmd("TextYankPost", {
	group = group,
	desc = "Highlight yanked text",
	callback = function()
		vim.hl.on_yank()
	end,
})

-- Restore the last cursor position when reopening a file, unless the mark points
-- past the end of the buffer (e.g. the file shrank since it was last edited).
vim.api.nvim_create_autocmd("BufReadPost", {
	group = group,
	desc = "Restore last cursor position",
	callback = function(args)
		local mark = vim.api.nvim_buf_get_mark(args.buf, "\"")
		local line_count = vim.api.nvim_buf_line_count(args.buf)

		if mark[1] > 0 and mark[1] <= line_count then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

-- Format-on-save is deliberately absent: nothing is installed yet that could do the
-- formatting. Add it together with whichever LSP or formatter lands first.
