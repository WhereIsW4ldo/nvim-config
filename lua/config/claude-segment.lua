-- The Claude plan-usage reading, formatted as a statusline section.
--
-- Rendering only. `config.claude-usage` owns the data and the refresh cycle, and calls
-- `redrawstatus` itself the moment a reading lands or an attempt fails, so nothing here
-- polls or schedules -- it is asked for a string and returns one.
--
-- Deliberately depends on no plugin, which is what lets it live in `config/`. It returns
-- `text, highlight_group`, the same shape `MiniStatusline.section_*` uses, so
-- `lua/plugin/statusline.lua` can drop it straight into a group list -- and a different
-- statusline could consume it unchanged.
local usage = require("config.claude-usage")

-- Percent of the 5-hour window at which the section stops being informational.
local WARN_AT = 70
local CRIT_AT = 90

-- Past this, a reading is dimmed whatever it says: the source refuses to refresh faster
-- than every 5 minutes, so anything much older than that is not describing the present.
local STALE_AFTER_S = 15 * 60

-- The statusline is rebuilt through `%!`, which has its result rescanned for statusline
-- items, so a literal percent sign has to reach the line doubled.
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


--- The section: empty until a reading arrives, dimmed once one goes stale.
---
--- Numbers outrank errors. A refresh that fails leaves the previous reading in place, so
--- whatever we hold is shown and merely marked -- the error text only appears when there
--- is nothing to show instead.
---
--- An empty string is a section `MiniStatusline.combine_groups` drops entirely, so the
--- "no reading yet" case costs no space on the line.
--- @return string  section text
--- @return string  highlight group for it
function M.section()
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
			return "", "StatusLineUsageDim"
		end

		-- curl's stderr reaches here verbatim and may contain a `%`, which the rescan
		-- would read as a statusline item. `%%%%` rather than `PERCENT`: `%` is special
		-- in a gsub replacement too, so it needs doubling twice over.
		local message = current.err:sub(1, 40):gsub("%%", "%%%%")
		return ("Claude %s"):format(message), "StatusLineUsageDim"
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

	-- `combine_groups` opens the group with `%#group#`; the label overrides that to dim
	-- and then switches back, so the reading keeps its own colour. Switching back
	-- explicitly rather than closing with `%*` matters -- `%*` restores the statusline's
	-- default highlight, not this group's.
	local label = ("%%#StatusLineUsageDim#Claude %%#%s#"):format(group)

	return label .. table.concat(parts, " "), group
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

usage.setup()

return M
