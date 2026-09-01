-- Fits every column of a `sqlcmd` result to the widest value actually in it.
--
-- Why this is here rather than a flag. go-sqlcmd has exactly two width controls,
-- `SQLCMDMAXFIXEDTYPEWIDTH` and `SQLCMDMAXVARTYPEWIDTH`, and both are *caps applied from
-- the column's declared type before a single row is read* -- nothing in it measures a
-- result set and fits to it. The two flags that could help indirectly, `-W` (trim trailing
-- spaces) and `-F` (output format), are the only formatting flags with no scripting
-- variable behind them, and `db#adapter#sqlserver#input()` is `interactive() + ['-i', file]`
-- with no formatting flags and no hook to add any. So `vim.env` cannot reach them, and the
-- fit has to happen after the fact, here.
--
-- What makes that safe is that the output carries its own geometry: the `----- ----` rule
-- under the header gives every column's exact start and end. Nothing is guessed. It is also
-- what keeps this from touching other adapters' output -- postgres rules its columns with
-- `-----+-----` and mysql with `+-----+`, neither of which parses as a rule line here, so
-- their buffers pass through untouched without this module knowing anything about them.
--
-- Compatible with dadbod-ui's own dbout features by construction rather than by luck:
-- `db_ui#dbout#get_cell_value` (`vic`), `yank_header` (`yh`), `jump_to_foreign_table`
-- (`<C-]>`) and `foldexpr` all read the column geometry out of the rule line in the buffer
-- at the moment they run. Rewriting header, rule and rows together keeps that geometry
-- internally consistent, so they simply operate on the narrower columns.
local M = {}


--- Bytes, characters and display cells all coincide for an ASCII line, which almost every
--- result line is -- and `string.sub` is far cheaper than a `vim.fn` round trip per cell on
--- a result set with thousands of rows. Anything else has to go the slow, correct way:
--- sqlcmd pads through Go's `%-*s`, whose width counts runes, not bytes.
local function is_ascii(line)
	return line:find("[\128-\255]") == nil
end


--- Display width of a value, by the same shortcut.
local function width(value)
	return is_ascii(value) and #value or vim.fn.strdisplaywidth(value)
end


--- The character positions of every column, read off a rule line, or nil when the line is
--- not one. A rule line is runs of dashes joined by exactly one space, and it ends on a
--- dash -- anything else (a postgres `-----+-----`, a row that happens to start with a
--- minus sign, a horizontal rule in a comment) is rejected here rather than downstream.
local function rule_columns(line)
	local columns  = {}
	local position = 1

	while true do
		local from, to = line:find("^%-+", position)
		if not from then
			return nil
		end

		columns[#columns + 1] = { from = from, to = to, }

		if to == #line then
			return columns
		end
		if line:sub(to + 1, to + 1) ~= " " then
			return nil
		end

		position = to + 2
		if position > #line then
			return nil
		end
	end
end


--- One raw, still-padded cell per column.
local function cells(line, columns)
	local ascii = is_ascii(line)
	local out   = {}

	for index, column in ipairs(columns) do
		if ascii then
			out[index] = line:sub(column.from, column.to)
		else
			out[index] = vim.fn.strcharpart(line, column.from - 1, column.to - column.from + 1)
		end
	end

	return out
end


--- Whether a line really carries the geometry the rule line describes. sqlcmd puts a space
--- at every column boundary and never emits a row wider than the rule, so a line that
--- breaks either rule is not a row -- a value with an embedded newline is the realistic
--- cause, and its continuation line would otherwise be sliced into nonsense.
---
--- A line that stops short is judged on where it stops. The only column sqlcmd can leave
--- unpadded is the last one, so a row may end anywhere inside that column -- but a line
--- ending before the last column even begins cannot be a row, whatever its gaps look like.
--- That is what catches the continuation line of a multi-line value, which would otherwise
--- pass by simply being too short to reach a boundary and disagree with it.
local function conforms(line, columns)
	local ascii  = is_ascii(line)
	local length = ascii and #line or vim.fn.strchars(line)

	if length > columns[#columns].to or length < columns[#columns].from - 1 then
		return false
	end

	for index = 1, #columns - 1 do
		local gap = columns[index].to + 1

		if gap <= length then
			local char = ascii and line:sub(gap, gap) or vim.fn.strcharpart(line, gap - 1, 1)
			if char ~= " " then
				return false
			end
		end
	end

	return true
end


--- Which edge sqlcmd padded a single cell against, or nil when it padded neither -- which
--- is what a value exactly filling its slot looks like, and it should vote for nothing.
--- The column's type is not in the output, so the padding is the only evidence of it:
--- numbers arrive right-aligned and text left-aligned, and re-aligning a numeric column to
--- the left would be a visible regression on what sqlcmd already got right.
local function side(value)
	local leading  = value:sub(1, 1) == " "
	local trailing = value:sub(-1) == " "

	if leading and not trailing then
		return "right"
	elseif trailing and not leading then
		return "left"
	end

	return nil
end


--- One line, padded to the new widths. Trailing whitespace goes: nothing is aligned against
--- the right edge of the last column, so keeping it only widens the buffer.
local function render(values, widths, aligns)
	local parts = {}

	for index, value in ipairs(values) do
		local padding = string.rep(" ", math.max(0, widths[index] - width(value)))
		parts[index]  = aligns[index] == "right" and padding .. value or value .. padding
	end

	return (table.concat(parts, " "):gsub("%s+$", ""))
end


--- Rewrite one header/rule/rows block in `lines`, in place. Returns whether it changed.
---
--- Deliberately a single pass over the cells, keeping the trimmed value and tallying the
--- alignment vote as it goes. The obvious two-pass shape -- measure, then trim again while
--- rewriting -- trims every cell twice, which is the whole cost on a result set large
--- enough for anyone to notice.
local function reflow_block(lines, header, rule, last, columns)
	local count  = #columns
	local head   = cells(lines[header], columns)
	local widths = {}
	local rights = {}
	local lefts  = {}
	local rows   = {}

	for index = 1, count do
		widths[index] = width(vim.trim(head[index]))
		rights[index] = 0
		lefts[index]  = 0
	end

	for line = rule + 1, last do
		local raw = cells(lines[line], columns)
		local row = {}

		for index = 1, count do
			local vote = side(raw[index])

			if vote == "right" then
				rights[index] = rights[index] + 1
			elseif vote == "left" then
				lefts[index] = lefts[index] + 1
			end

			local value = vim.trim(raw[index])
			local cell  = width(value)
			row[index]  = value

			if cell > widths[index] then
				widths[index] = cell
			end
		end

		rows[#rows + 1] = row
	end

	-- A column whose header and every value are empty would otherwise get a zero-width rule,
	-- which is no longer a rule line and would break the next parse of this buffer.
	local shrunk = false

	for index, column in ipairs(columns) do
		widths[index] = math.max(widths[index], 1)
		shrunk        = shrunk or widths[index] < column.to - column.from + 1
	end

	if not shrunk then
		return false
	end

	-- The header keeps its own alignment rather than the column's: sqlcmd left-aligns the
	-- header of a right-aligned numeric column, and that is worth preserving.
	local head_aligns = {}
	local head_values = {}
	local rule_cells  = {}
	local aligns      = {}

	for index = 1, count do
		head_aligns[index] = side(head[index]) or "left"
		head_values[index] = vim.trim(head[index])
		rule_cells[index]  = string.rep("-", widths[index])
		aligns[index]      = rights[index] > lefts[index] and "right" or "left"
	end

	lines[header] = render(head_values, widths, head_aligns)
	lines[rule]   = table.concat(rule_cells, " ")

	for offset, row in ipairs(rows) do
		lines[rule + offset] = render(row, widths, aligns)
	end

	return true
end


--- Fit every result block in a dbout buffer. A buffer with nothing recognisable in it is
--- left exactly as it arrived, which is also what happens on the first load of the output
--- file -- dadbod creates it empty and only fills it when the query returns.
function M.reflow(bufnr)
	local lines   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local changed = false
	local index   = 2

	while index <= #lines do
		local columns = rule_columns(lines[index])

		if not columns then
			index = index + 1
		else
			local header = index - 1
			local stop   = index + 1
			local safe   = true

			while stop <= #lines do
				local line = lines[stop]

				-- A blank line ends a result set, and `(N rows affected)` follows it. Neither
				-- is a row, and neither means the block was malformed.
				if line:match("^%s*$") or line:match("^%(%d+ rows? affected%)") then
					break
				end
				if not conforms(line, columns) then
					safe = false
					break
				end

				stop = stop + 1
			end

			-- All or nothing per block. Reflowing the rows up to a line that broke the
			-- geometry and leaving the rest at the old width would look far worse than not
			-- touching the block at all, and would lose the alignment sqlcmd did get right.
			if safe and conforms(lines[header], columns) then
				changed = reflow_block(lines, header, index, stop - 1, columns) or changed
			end

			index = stop
		end
	end

	if not changed then
		return
	end

	-- `s:init()` in vim-dadbod leaves the buffer `readonly nomodifiable`, and those are
	-- buffer-local so they survive the `:edit!` that reloads the file once the query returns.
	-- `modified` goes back to false deliberately: the temp file on disk keeps sqlcmd's own
	-- output, and this buffer is not something anyone should be prompted to save.
	local modifiable = vim.bo[bufnr].modifiable

	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = modifiable
	vim.bo[bufnr].modified   = false
end

return M
