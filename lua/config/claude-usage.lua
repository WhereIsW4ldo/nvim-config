-- Plan usage for the Claude subscription that `lua/plugin/ai.lua` talks to.
--
-- The percentages `/usage` shows reach a *terminal* statusline through the CLI's stdin
-- payload (`rate_limits.five_hour.used_percentage`) and through nothing else -- hook
-- payloads carry only `{ session_id, transcript_path, cwd, prompt_id, permission_mode,
-- agent_id, agent_type, effort }`. Sessions here run over ACP, which never renders a
-- statusline, so that route is closed. Two sources are left, and this module uses both:
--
--   1. `~/.claude.json`'s `cachedUsageUtilization` -- what the CLI persists after its own
--      fetches. Free, needs no token, and instantly available at startup. It is also the
--      CLI's fallback for exactly this purpose. But it goes stale: the CLI refuses to
--      rewrite it more often than every 5 minutes and treats it as valid for a full hour,
--      and an ACP-only session may not refresh it at all.
--   2. `GET https://api.anthropic.com/api/oauth/usage` -- the endpoint the CLI's own
--      `fetchUtilization` calls, authenticated with the OAuth token in
--      `~/.claude/.credentials.json`. Current, but rate-limited: polling it every minute
--      earns an HTTP 429.
--
-- So: adopt the cache whenever it is ahead of what we hold, and only spend a request when
-- the cache has not kept up. That means no request at all while something else is keeping
-- the cache warm, and a 5-minute cadence -- the CLI's own throttle -- when nothing is.
-- A 429 backs off geometrically to an hour, honouring `Retry-After` when it is sent.
--
-- A failed fetch never discards the last good reading; it only marks it, so a transient
-- 429 shows slightly old percentages instead of blanking the statusline.
--
-- The token goes to curl over stdin via `--config -`, never as an argument, so it stays
-- out of the process list.
local ENDPOINT         = "https://api.anthropic.com/api/oauth/usage"
local CREDENTIALS_PATH = vim.fn.expand "~/.claude/.credentials.json"
local CACHE_PATH       = vim.fn.expand "~/.claude.json"

-- Starting cadence, matching the CLI's own minimum interval between cache writes (`fe_`).
-- Only a starting point: the endpoint advertises no budget -- a 200 carries no
-- `Retry-After` and no `anthropic-ratelimit-*` header -- so the sustainable rate can only
-- be discovered by being refused, and `interval_ms` below adapts to it.
local REFRESH_MS     = 5 * 60 * 1000
local BACKOFF_MAX_MS = 60 * 60 * 1000
local TIMEOUT_S      = "5"

-- Wrappers the CLI has nested its OAuth block under. Tried in order, then the top level,
-- so a rename on the CLI side degrades to "no token" rather than an error on every redraw.
local TOKEN_WRAPPERS = { "claudeAiOauth", "oauthAccount", }

--- @class ClaudeUsage
--- @field five_hour  integer|nil  percent of the 5-hour window used
--- @field seven_day  integer|nil  percent of the weekly window used
--- @field resets_at  integer|nil  epoch seconds at which the 5-hour window rolls over
--- @field fetched_at integer|nil  epoch seconds the reading was taken
--- @field source     string|nil   "cache" or "api"
--- @field err        string|nil   why the *last attempt* produced nothing; data may still be set
local state = {}

local in_flight = false
local raw_body  = nil
local timer     = nil

-- Cadence for this session. Raised, and never lowered again, each time the endpoint refuses
-- us: springing back to `REFRESH_MS` after a 429 would just earn another one next cycle.
local interval_ms = REFRESH_MS

-- Extra delay after a failure, on top of `interval_ms`. Cleared by the next success.
local backoff_ms = nil

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


--- Picks the two windows worth showing out of a utilization object.
---
--- The API response and the persisted cache share this shape, so both go through here:
--- top-level `five_hour` / `seven_day`, each with `utilization` as a percentage 0-100 and
--- `resets_at` as an ISO 8601 instant. The parallel `limits[]` array carries the same
--- figures under codenames (`session`, `weekly_all`) and is deliberately ignored.
---
--- Either window can be null, as can a handful of codenamed ones (`tangelo`,
--- `nimbus_quill`, ...) that are not ours to interpret. `vim.json.decode` renders those as
--- `vim.NIL`, which the type checks below reject.
--- @return ClaudeUsage|nil
local function parse_windows(decoded)
	if type(decoded) ~= "table" then
		return nil
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
		return nil
	end

	return parsed
end


--- The CLI's persisted reading, if it is newer than what we already hold.
--- @return ClaudeUsage|nil
local function read_cache()
	local ok, lines = pcall(vim.fn.readfile, CACHE_PATH)
	if not ok then
		return nil
	end

	local decoded
	ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local cached = decoded.cachedUsageUtilization
	if type(cached) ~= "table" or type(cached.fetchedAtMs) ~= "number" then
		return nil
	end

	local parsed = parse_windows(cached.utilization)
	if not parsed then
		return nil
	end

	parsed.fetched_at = math.floor(cached.fetchedAtMs / 1000)
	parsed.source     = "cache"

	return parsed
end


--- Replaces the reading, clearing any previous failure.
local function adopt(parsed)
	state = parsed
	vim.cmd.redrawstatus()
end


--- @return boolean  whether the held reading is recent enough to skip a request
local function fresh_enough()
	if not state.fetched_at then
		return false
	end

	return (os.time() - state.fetched_at) < (interval_ms / 1000)
end


local function schedule(delay_ms)
	if not timer then
		return
	end

	timer:stop()
	timer:start(delay_ms, 0, function()
		vim.schedule(M.tick)
	end)
end


--- Records a failure without discarding the last good reading, and slows the next attempt.
---
--- `throttled` is reserved for a 429: that is the endpoint saying the *base* cadence is too
--- fast, so it raises `interval_ms` for good. Ordinary failures -- a dropped connection, an
--- expired token -- only delay the next attempt, since they say nothing about the rate.
local function fail(message, retry_after_s, throttled)
	state.err = message or "unknown error"

	if throttled then
		interval_ms = math.min(interval_ms * 2, BACKOFF_MAX_MS)
	end

	local from_header = retry_after_s and (retry_after_s * 1000) or 0
	local doubled     = (backoff_ms or interval_ms) * 2
	backoff_ms        = math.min(math.max(from_header, doubled), BACKOFF_MAX_MS)

	vim.cmd.redrawstatus()
	schedule(backoff_ms)
end


--- Fetches once, asynchronously. Overlapping calls are dropped rather than queued.
function M.refresh()
	if in_flight then
		return
	end

	local token, reason = read_token()
	if not token then
		fail(reason)
		return
	end

	in_flight = true

	-- The status code and `Retry-After` arrive on their own trailing lines rather than via
	-- `--fail`, which would discard the body that explains a rejection.
	local command = {
		"curl",
		"--silent",
		"--show-error",
		"--max-time", TIMEOUT_S,
		"--write-out", "\n%{http_code}\n%header{retry-after}",
		"--config", "-",
		ENDPOINT,
	}
	local stdin = ('header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n')
		:format(token)

	vim.system(command, { text = true, stdin = stdin, }, function(result)
		vim.schedule(function()
			in_flight = false

			if result.code ~= 0 then
				fail("curl failed: " .. vim.trim(result.stderr or ""))
				return
			end

			local body, status, retry_after = (result.stdout or ""):match "^(.*)\n(%d+)\n(.-)$"
			raw_body                        = body or result.stdout

			if status ~= "200" then
				fail("HTTP " .. (status or "?"), tonumber(vim.trim(retry_after or "")), status == "429")
				return
			end

			local decoded_ok, decoded = pcall(vim.json.decode, body)
			local parsed              = decoded_ok and parse_windows(decoded) or nil
			if not parsed then
				fail "unparseable response"
				return
			end

			parsed.fetched_at = os.time()
			parsed.source     = "api"
			backoff_ms        = nil

			adopt(parsed)
			schedule(interval_ms)
		end)
	end)
end


--- Takes the cheapest route to a current reading, then arranges the next check.
function M.tick()
	local cached = read_cache()
	if cached and (not state.fetched_at or cached.fetched_at > state.fetched_at) then
		adopt(cached)
	end

	if fresh_enough() then
		schedule(backoff_ms or interval_ms)
		return
	end

	M.refresh()
end


--- @return ClaudeUsage
function M.get()
	return state
end


--- Starts the refresh cycle and registers the two commands. Idempotent per session.
function M.setup()
	timer = assert(vim.uv.new_timer())
	schedule(200)

	local group = vim.api.nvim_create_augroup("ClaudeUsage", { clear = true, })
	vim.api.nvim_create_autocmd("FocusGained", {
		group    = group,
		desc     = "Check Claude plan usage when Neovim regains focus",
		callback = function() M.tick() end,
	})

	-- Clears the backoff but not `interval_ms`: a manual retry should be immediate without
	-- discarding what the endpoint has already taught us about a sustainable rate.
	vim.api.nvim_create_user_command("ClaudeUsage", function()
		backoff_ms = nil
		M.refresh()
		vim.notify(("%s\ninterval: %ds"):format(vim.inspect(state), interval_ms / 1000), vim.log.levels.INFO)
	end, { desc = "Force a Claude plan usage refresh and report state", })

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
