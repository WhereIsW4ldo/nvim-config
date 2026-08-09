-- Plan usage for the Claude subscription that `lua/plugin/ai.lua` talks to.
--
-- The percentages `/usage` shows reach a *terminal* statusline through the CLI's stdin
-- payload (`rate_limits.five_hour.used_percentage`) and through nothing else -- hook
-- payloads carry only `{ session_id, transcript_path, cwd, prompt_id, permission_mode,
-- agent_id, agent_type, effort }`. Sessions here run over ACP, which never renders a
-- statusline, so that route is closed. This module goes to the source the CLI itself
-- uses (its `fetchUtilization`):
--
--   GET https://api.anthropic.com/api/oauth/usage
--
-- authenticated with the OAuth access token the CLI keeps in `~/.claude/.credentials.json`.
-- Two consequences are worth knowing:
--
--   * The endpoint is internal. The CLI's own schema for it carries the note "the response
--     shape may change", so `:ClaudeUsageDebug` shows the raw JSON for when the numbers
--     stop making sense.
--   * Renewing that token is the refresh-token flow, which belongs to the CLI. Neovim only
--     ever reads the file. An expired token means a 401 and a stale reading until the CLI
--     renews it -- which it does on its own next request.
--
-- The token is handed to curl over stdin via `--config -`, not as an argument, so it never
-- appears in the process list.
local ENDPOINT         = "https://api.anthropic.com/api/oauth/usage"
local CREDENTIALS_PATH = vim.fn.expand "~/.claude/.credentials.json"
local REFRESH_MS       = 60 * 1000
local TIMEOUT_S        = "5"

-- Wrappers the CLI has nested its OAuth block under. Tried in order, then the top level,
-- so a rename on the CLI side degrades to "no token" rather than an error on every redraw.
local TOKEN_WRAPPERS = { "claudeAiOauth", "oauthAccount", }

--- @class ClaudeUsage
--- @field five_hour integer|nil  percent of the 5-hour window used
--- @field seven_day integer|nil  percent of the weekly window used
--- @field resets_at integer|nil  epoch seconds at which the 5-hour window rolls over
--- @field err       string|nil   why the last fetch produced nothing
local state = {}

local in_flight = false
local raw_body  = nil

local M = {}


--- Reads the OAuth access token off disk. Returns nil plus a reason when there is none.
--- @return string|nil, string|nil
local function read_token()
	local ok, lines = pcall(vim.fn.readfile, CREDENTIALS_PATH)
	if not ok then
		return nil, "no ~/.claude/.credentials.json"
	end

	local decoded
	ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok or type(decoded) ~= "table" then
		return nil, "unreadable credentials"
	end

	for _, wrapper in ipairs(TOKEN_WRAPPERS) do
		local node = decoded[wrapper]
		if type(node) == "table" and type(node.accessToken) == "string" then
			return node.accessToken, nil
		end
	end

	if type(decoded.accessToken) == "string" then
		return decoded.accessToken, nil
	end

	return nil, "no access token in credentials"
end


--- Converts an ISO 8601 instant to epoch seconds.
---
--- `os.time` reads its table as local time, so the result is shifted by the local offset
--- and corrected here. A trailing `Z`, an explicit `+HH:MM`, and a bare timestamp (assumed
--- UTC) are all accepted.
--- @return integer|nil
local function iso_to_epoch(iso)
	if type(iso) ~= "string" then
		return nil
	end

	local year, month, day, hour, min, sec = iso:match "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
	if not year then
		return nil
	end

	local as_local = os.time({
		year  = tonumber(year),
		month = tonumber(month),
		day   = tonumber(day),
		hour  = tonumber(hour),
		min   = tonumber(min),
		sec   = tonumber(sec),
		isdst = false,
	})
	if not as_local then
		return nil
	end

	local now  = os.time()
	local skew = os.time(os.date("!*t", now)) - now
	local at   = as_local - skew

	local sign, off_hour, off_min = iso:match "([+-])(%d%d):(%d%d)$"
	if sign then
		local offset = (tonumber(off_hour) * 3600) + (tonumber(off_min) * 60)
		at = at + (sign == "-" and offset or -offset)
	end

	return at
end


--- Picks the two windows worth showing out of the response.
---
--- The top-level `five_hour` / `seven_day` objects are the ones the CLI's own statusline
--- schema documents: `utilization` as a percentage 0-100, `resets_at` as an ISO 8601
--- instant. The parallel `limits[]` array carries the same figures under codenames
--- (`session`, `weekly_all`) and is deliberately ignored.
---
--- Either window can be null -- and every response also carries a handful of null
--- codenamed windows (`tangelo`, `nimbus_quill`, ...) that are not ours to interpret.
--- `vim.json.decode` renders those as `vim.NIL`, which the type checks below reject.
--- @return ClaudeUsage|nil, string|nil
local function parse(body)
	local ok, decoded = pcall(vim.json.decode, body)
	if not ok or type(decoded) ~= "table" then
		return nil, "unparseable response"
	end

	local function window(name)
		local node = decoded[name]
		if type(node) ~= "table" then
			return nil, nil
		end

		local percent = tonumber(node.utilization)
		return percent and math.floor(percent + 0.5) or nil, iso_to_epoch(node.resets_at)
	end

	local parsed = {}
	parsed.five_hour, parsed.resets_at = window "five_hour"
	parsed.seven_day                   = window "seven_day"

	if not parsed.five_hour and not parsed.seven_day then
		return nil, "no five_hour or seven_day window"
	end

	return parsed, nil
end


--- Fetches once, asynchronously. Overlapping calls are dropped rather than queued.
function M.refresh()
	if in_flight then
		return
	end

	local token, reason = read_token()
	if not token then
		state = { err = reason, }
		return
	end

	in_flight = true

	-- `%{http_code}` on its own trailing line, so a 401 is distinguishable from a network
	-- failure without `--fail`, which would discard the body that explains why.
	local command = {
		"curl",
		"--silent",
		"--show-error",
		"--max-time", TIMEOUT_S,
		"--write-out", "\n%{http_code}",
		"--config", "-",
		ENDPOINT,
	}
	local stdin = ('header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n')
		:format(token)

	vim.system(command, { text = true, stdin = stdin, }, function(result)
		vim.schedule(function()
			in_flight = false

			if result.code ~= 0 then
				state = { err = "curl failed: " .. vim.trim(result.stderr or ""), }
				return
			end

			local body, status = (result.stdout or ""):match "^(.*)\n(%d+)$"
			raw_body           = body

			if status ~= "200" then
				state = { err = "HTTP " .. (status or "?"), }
				return
			end

			local parsed, reason = parse(body)
			state = parsed or { err = reason, }

			vim.cmd.redrawstatus()
		end)
	end)
end


--- @return ClaudeUsage
function M.get()
	return state
end


--- Starts the refresh timer and registers the two commands. Idempotent per session.
function M.setup()
	local timer = assert(vim.uv.new_timer())
	timer:start(200, REFRESH_MS, function()
		vim.schedule(M.refresh)
	end)

	local group = vim.api.nvim_create_augroup("ClaudeUsage", { clear = true, })
	vim.api.nvim_create_autocmd("FocusGained", {
		group    = group,
		desc     = "Refresh Claude plan usage when Neovim regains focus",
		callback = function() M.refresh() end,
	})

	vim.api.nvim_create_user_command("ClaudeUsage", function()
		M.refresh()
		vim.notify(vim.inspect(state), vim.log.levels.INFO)
	end, { desc = "Refresh and report Claude plan usage", })

	vim.api.nvim_create_user_command("ClaudeUsageDebug", function()
		if not raw_body then
			vim.notify("No response captured yet -- run :ClaudeUsage first", vim.log.levels.WARN)
			return
		end

		vim.cmd "new"
		vim.bo.buftype  = "nofile"
		vim.bo.filetype = "json"
		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(raw_body, "\n"))
	end, { desc = "Show the raw /api/oauth/usage response", })
end


return M
