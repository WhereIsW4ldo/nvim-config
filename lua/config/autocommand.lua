local api = vim.api

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

-- Diagnostic refresh
vim.api.nvim_create_autocmd({ "InsertLeave", }, {
	pattern = "*",
	callback = function()
		local clients = vim.lsp.get_clients({ name = "roslyn", })
		if not clients or #clients == 0 then
			return
		end

		for _, client in ipairs(clients) do
			local buffers = vim.lsp.get_buffers_by_client_id(client.id)
			for _, buf in ipairs(buffers) do
				local params = { textDocument = vim.lsp.util.make_text_document_params(buf), }
				client:request("textDocument/diagnostic", params, nil, buf)
			end
		end
	end,
})
