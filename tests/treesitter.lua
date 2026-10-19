-- Run with: nvim --headless "+luafile tests/treesitter.lua"
local function test()
	vim.lsp.enable("powershell_es", false)

	local semantic_enabled = vim.lsp.semantic_tokens.enable
	local semantic_call
	vim.lsp.semantic_tokens.enable = function(enabled, filter)
		semantic_call = { enabled = enabled, filter = filter, }
	end
	vim.lsp.config.powershell_es.on_attach({ id = 123, }, 456)
	vim.lsp.semantic_tokens.enable = semantic_enabled
	assert(semantic_call and semantic_call.enabled == false, "PowerShell semantic coloring was not disabled")
	assert(semantic_call.filter.bufnr == 456, "Semantic coloring opt-out is not buffer-scoped")
	assert(semantic_call.filter.client_id == 123, "Semantic coloring opt-out is not client-scoped")

	local lines = {
		"<#",
		".SYNOPSIS",
		"    Resources declared with the bicep 'existing' keyword are skipped.",
		"",
		".EXAMPLE",
		"    ./Get-Resources.ps1 -TemplateFile ./main.bicep",
		"#>",
		"[CmdletBinding()]",
		"param(",
		"\t[ValidateSet('Resource Group', 'Subscription', 'Management Group')]",
		"\t[string] $DeploymentScope",
		")",
		"Write-Output \"Scope: $DeploymentScope\"",
	}
	local buffers = {}
	local function open()
		local buf = vim.api.nvim_create_buf(true, false)
		buffers[#buffers + 1] = buf
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = "ps1"
		return buf
	end


	local function captured(row, col, name)
		for _, capture in ipairs(vim.treesitter.get_captures_at_pos(0, row, col)) do
			if capture.capture == name then
				return true
			end
		end
		return false
	end


	local buf = open()
	assert(vim.treesitter.highlighter.active[buf], "PowerShell highlighter did not start")
	assert(not vim.treesitter.get_parser():parse()[1]:root():has_error(), "Sample failed to parse")
	for col = 0, #lines[3] - 1 do
		assert(captured(2, col, "comment"), "Block comment lost highlighting at column " .. col)
	end
	assert(captured(9, 16, "string"), "ValidateSet string is not highlighted")
	assert(captured(10, 12, "variable.parameter"), "Parameter is not highlighted")
	assert(captured(12, 15, "string"), "Expandable string is not highlighted")

	-- Editing above the comment and reopening must not lose the multiline context.
	vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "# heading", })
	vim.treesitter.get_parser():parse()
	assert(captured(3, 20, "comment"), "Comment highlighting broke after an edit")
	vim.cmd.enew()
	vim.api.nvim_set_current_buf(buf)
	assert(captured(3, 20, "comment"), "Comment highlighting broke after switching buffers")

	local get_files = vim.treesitter.query.get_files
	local notify = vim.notify
	local warning
	vim.treesitter.query.get_files = function(language, query, ...)
		if language == "powershell" and query == "highlights" then
			return {}
		end
		return get_files(language, query, ...)
	end
	vim.notify = function(message, level)
		warning = { message, level, }
	end
	local missing = open()
	vim.treesitter.query.get_files = get_files
	vim.notify = notify

	assert(not vim.treesitter.highlighter.active[missing], "Started a highlighter without queries")
	assert(vim.bo[missing].syntax == "ps1", "Missing queries disabled the fallback syntax")
	assert(warning and warning[2] == vim.log.levels.WARN, "Missing queries were not reported")
	assert(warning[1]:find(":TSInstall! powershell", 1, true), "Warning lacks the repair command")
	local syntax = vim.fn.synIDattr(vim.fn.synID(3, 20, 1), "name")
	assert(syntax == "ps1Comment", "Fallback did not highlight the block comment: " .. syntax)

	for _, buffer in ipairs(buffers) do
		vim.api.nvim_buf_delete(buffer, { force = true, })
	end
end


local ok, err = xpcall(test, debug.traceback)
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd.cquit()
end
print("Tree-sitter PowerShell highlighting checks passed")
vim.cmd.qa()
