-- One global statusline for the whole editor, carrying the Claude plan-usage readout.
--
-- Hand-written on purpose: a statusline plugin is not part of this config yet, and a
-- segment is the whole requirement. `%<%f %h%w%m%r%=%-14.(%l,%c%V%) %P` is Neovim's
-- built-in default (`:help 'statusline'`), reproduced here because assigning `statusline`
-- at all replaces the default wholesale. Everything else on the line is unchanged.
--
-- When a statusline plugin does arrive it takes this file's place: it owns `statusline`,
-- and the segment moves into its section list as a call to `claude-usage`.
local usage = require("config.claude-usage")

-- Percent of the 5-hour window at which the segment stops being informational.
local WARN_AT = 70
local CRIT_AT = 90

-- Past this, a reading is dimmed whatever it says: the source refuses to refresh faster
-- than every 5 minutes, so anything much older than that is not describing the present.
local STALE_AFTER_S = 15 * 60

-- `%!` has its result rescanned for statusline items, so a literal percent sign has to
-- reach the line doubled.
local PERCENT = "%%"

local M = {}


--- Renders a duration as `1h12m` / `47m` / `<1m`. Returns nil once it is in the past.
--- @return string|nil
local function countdown(epoch)
	local remaining = epoch - os.time()
	if remaining <= 0 then
		return nil
	end

	local hours   = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)

	if hours > 0 then
		return ("%dh%02dm"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%dm"):format(minutes)
	end

	return "<1m"
end


--- @return string  highlight group name for a 5-hour percentage
local function group_for(percent)
	if percent >= CRIT_AT then
		return "StatusLineUsageCrit"
	elseif percent >= WARN_AT then
		return "StatusLineUsageWarn"
	end

	return "StatusLineUsageOk"
end


--- The Claude segment: empty until a reading arrives, dimmed once one goes stale.
---
--- Numbers outrank errors. A refresh that fails leaves the previous reading in place, so
--- whatever we hold is shown and merely marked -- the error text only appears when there
--- is nothing to show instead.
--- @return string
local function segment()
	local current = usage.get()
	local parts   = {}

	if current.five_hour then
		table.insert(parts, ("5h %d%s"):format(current.five_hour, PERCENT))

		local resets = current.resets_at and countdown(current.resets_at)
		if resets then
			table.insert(parts, ("(resets %s)"):format(resets))
		end
	end

	if current.seven_day then
		local separator = #parts > 0 and "· " or ""
		table.insert(parts, ("%s7d %d%s"):format(separator, current.seven_day, PERCENT))
	end

	if #parts == 0 then
		if not current.err then
			return ""
		end

		-- curl's stderr reaches here verbatim and may contain a `%`, which the rescan
		-- would read as a statusline item. `%%%%` rather than `PERCENT`: `%` is special
		-- in a gsub replacement too, so it needs doubling twice over.
		local message = current.err:sub(1, 40):gsub("%%", "%%%%")
		return ("%%#StatusLineUsageDim#Claude %s%%*"):format(message)
	end

	-- `!` for a known failure, plain dimming for a reading that is merely getting old.
	local age   = current.fetched_at and (os.time() - current.fetched_at) or math.huge
	local group = group_for(current.five_hour or current.seven_day)

	if current.err then
		table.insert(parts, "!")
		group = "StatusLineUsageDim"
	elseif age > STALE_AFTER_S then
		group = "StatusLineUsageDim"
	end

	return ("%%#StatusLineUsageDim#Claude %%*%%#%s#%s%%*")
		:format(group, table.concat(parts, " "))
end


--- @return string
function M.render()
	return table.concat({
		"%<%f %h%w%m%r",
		"%=",
		segment(),
		"  ",
		"%-14.(%l,%c%V%) %P",
	})
end


--- `default = true` so a colorscheme that defines these groups itself wins.
local function set_highlights()
	vim.api.nvim_set_hl(0, "StatusLineUsageDim", { link = "Comment", default = true, })
	vim.api.nvim_set_hl(0, "StatusLineUsageOk", { link = "Comment", default = true, })
	vim.api.nvim_set_hl(0, "StatusLineUsageWarn", { link = "DiagnosticWarn", default = true, })
	vim.api.nvim_set_hl(0, "StatusLineUsageCrit", { link = "DiagnosticError", default = true, })
end


set_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
	group    = vim.api.nvim_create_augroup("StatusLineUsage", { clear = true, }),
	desc     = "Re-link statusline usage highlights after a colorscheme change",
	callback = set_highlights,
})

vim.o.laststatus = 3
vim.o.statusline = "%!v:lua.require'config.statusline'.render()"

usage.setup()

return M
