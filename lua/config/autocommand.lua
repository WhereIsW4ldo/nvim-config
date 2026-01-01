local api = vim.api
local keymap = vim.keymap

-- Quit fileExplorer if last
api.nvim_create_autocmd("QuitPre", {
	callback = function()
		local tree_wins = {}
		local floating_wins = {}
		local wins = vim.api.nvim_list_wins()
		for _, w in ipairs(wins) do
			local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
			if bufname:match("NvimTree_") ~= nil then
				table.insert(tree_wins, w)
			end
			if vim.api.nvim_win_get_config(w).relative ~= "" then
				table.insert(floating_wins, w)
			end
		end
		if 1 == #wins - #floating_wins - #tree_wins then
			-- Should quit, so we close all invalid windows.
			for _, w in ipairs(tree_wins) do
				vim.api.nvim_win_close(w, true)
			end
		end
	end,
})

-- Format on save
api.nvim_create_autocmd("BufWritePre", {
	pattern = "*",
	callback = function()
		vim.lsp.buf.format({ async = false, })
	end,
})

-- Add ';' automatically when starting insert on buffer
-- of filetype `cs`
--

local function get_closing_paren_pos_ts(bufnr, row, col)
	local ts_utils = vim.treesitter
	bufnr = bufnr or 0

	local cursor_row = row - 1
	local cursor_col = col - 1

	local parser = ts_utils.get_parser(bufnr)
	if not parser then
		return nil
	end

	local tree = parser:parse()[1]
	local root = tree:root()

	local node = root:named_descendant_for_range(
		cursor_row,
		cursor_col,
		cursor_row,
		cursor_col
	)

	while node do
		local type = node:type()

		if type == "string_literal_content" then
			return nil
		end

		if type == "expression_statement" or type == "argument_list" then
			local _, _, er, ec = node:range()

			-- The closing paren is usually the last character
			-- We move one char left from the node end
			return { er + 1, ec, } -- back to 1-based indexing
		end

		node = node:parent()
	end

	return nil
end

local function backup_print_semi(bufnr, row, col)
	api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { ";", })
	local new_cursor_pos = { row, col + 1, }
	api.nvim_win_set_cursor(0, new_cursor_pos)
end

api.nvim_create_autocmd("InsertEnter", {
	pattern = "*.cs",
	callback = function()
		print("autocmd linked to this buffer!")
		keymap.set("i", ";", function()
			local bufnr = 0
			local row, col = unpack(api.nvim_win_get_cursor(bufnr))

			local pos = get_closing_paren_pos_ts(bufnr, row, col)
			if not pos then return backup_print_semi(bufnr, row, col) end

			local line = api.nvim_get_current_line()
			local nline = line .. ";"
			api.nvim_set_current_line(nline)
			vim.cmd("normal $")
			print("added `;` to cs file")
		end, {
			desc = "Automatically place ';' when in `.cs` file",
			buffer = true,
		})
	end,
})
