local M = {}

---@return vim.lsp.util.open_floating_preview.Opts
function M.options()
	return {
		border     = "rounded",
		wrap       = true,
		focusable  = true,
		max_width  = math.max(1, math.floor(vim.o.columns * 0.7)),
		max_height = math.max(1, math.floor((vim.o.lines - vim.o.cmdheight - 2) * 0.5)),
	}
end

-- Concealed link destinations still count toward soft wrapping, so long
-- jdt:// or file:// URLs leave blank rows; keep only the link text.
---@param lines string[]
---@return string[]
local function strip_link_targets(lines)
	-- jdtls destinations can hold unbalanced parentheses, so a destination is
	-- the non-space run up to its last ")".
	return vim.tbl_map(function(line)
		return (line:gsub("%[([^%]]*)%]%((<?%a[%w+.-]*:%S*)%)", function(text, target)
			return not target:find("%)%S") and text or nil
		end))
	end, lines)
end


function M.hover()
	local config    = M.options()
	config.focus_id = "textDocument/hover"
	local params    = function(client)
		return vim.lsp.util.make_position_params(0, client.offset_encoding)
	end

	vim.lsp.buf_request_all(0, "textDocument/hover", params, function(results, ctx)
		if ctx.bufnr ~= vim.api.nvim_get_current_buf() then
			return
		end

		local hovers = {}
		for client_id, resp in pairs(results) do
			if resp.err then
				vim.lsp.log.error(resp.err.code, resp.err.message)
			elseif resp.result and resp.result.contents then
				local lines = vim.lsp.util.convert_input_to_markdown_lines(resp.result.contents)
				if #table.concat(lines) > 0 then
					hovers[#hovers + 1] = { client_id = client_id, contents = resp.result.contents, lines = lines, }
				end
			end
		end

		if #hovers == 0 then
			vim.notify("No information available", vim.log.levels.INFO)
			return
		end

		local format   = "markdown"
		local contents = {}
		for _, hover in ipairs(hovers) do
			local plaintext = type(hover.contents) == "table" and hover.contents.kind == "plaintext"
			if #hovers > 1 then
				contents[#contents + 1] = "# " .. vim.lsp.get_client_by_id(hover.client_id).name
			end
			if plaintext and #hovers == 1 then
				format   = "plaintext"
				contents = vim.split(hover.contents.value, "\n", { trimempty = true, })
			elseif plaintext then
				contents[#contents + 1] = "```"
				vim.list_extend(contents, vim.split(hover.contents.value, "\n", { trimempty = true, }))
				contents[#contents + 1] = "```"
			else
				vim.list_extend(contents, strip_link_targets(hover.lines))
			end
			contents[#contents + 1] = "---"
		end
		contents[#contents] = nil

		vim.lsp.util.open_floating_preview(contents, format, config)
	end)
end

---@param client vim.lsp.Client
---@param bufnr integer
function M.attach(client, bufnr)
	if client:supports_method("textDocument/hover", bufnr) then
		vim.keymap.set("n", "K", M.hover, { buffer = bufnr, desc = "Hover documentation", })
	end

	if client:supports_method("textDocument/signatureHelp", bufnr) then
		vim.keymap.set("i", "<C-s>", function()
			vim.lsp.buf.signature_help(M.options())
		end, { buffer = bufnr, desc = "Signature help", })
	end
end

function M.scroll(key)
	local preview = vim.b.lsp_floating_preview
	local command = { args = { tostring(vim.v.count1) .. vim.keycode(key), }, bang = true, }

	if preview and vim.api.nvim_win_is_valid(preview) then
		vim.api.nvim_win_call(preview, function()
			vim.cmd.normal(command)
		end)
	else
		vim.cmd.normal(command)
	end
end

return M
