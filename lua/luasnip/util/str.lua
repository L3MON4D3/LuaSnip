-- Some string processing utility functions
local M = {}

---In-place dedents strings in lines.
---@param lines string[].
local function dedent(lines)
	if #lines > 0 then
		local ind_size = math.huge
		for i, _ in ipairs(lines) do
			local i1, i2 = lines[i]:find("^%s*[^%s]")
			if i1 and i2 < ind_size then
				ind_size = i2
			end
		end
		for i, _ in ipairs(lines) do
			lines[i] = lines[i]:sub(ind_size, -1)
		end
	end
end

---Applies opts to lines.
---lines is modified in-place.
---@param lines string[].
---@param options table, required, can have values:
---  - trim_empty: removes empty first and last lines.
---  - dedent: removes indent common to all lines.
function M.process_multiline(lines, options)
	if options.trim_empty then
		if lines[1]:match("^%s*$") then
			table.remove(lines, 1)
		end
		if #lines > 0 and lines[#lines]:match("^%s*$") then
			lines[#lines] = nil
		end
	end

	if options.dedent then
		dedent(lines)
	end
end

function M.dedent(s)
	local lst = vim.split(s, "\n")
	dedent(lst)
	return table.concat(lst, "\n")
end

local function is_escaped(s, indx)
	local count = 0
	for i = indx - 1, 1, -1 do
		if string.sub(s, i, i) == "\\" then
			count = count + 1
		else
			break
		end
	end
	return count % 2 == 1
end

--- return position of next (relative to `start`) unescaped occurence of
--- `target` in `s`.
---@param s string
---@param target string
---@param start number
local function find_next_unescaped(s, target, start)
	while true do
		local from = s:find(target, start, true)
		if not from then
			return nil
		end
		if not is_escaped(s, from) then
			return from
		end
		start = from + 1
	end
end

--- Creates iterator that returns all positions of substrings <left>.*<right>
--- in `s`, where left and right are not escaped.
--- Only complete pairs left,right are returned, an unclosed left is ignored.
---@param s string
---@param left string
---@param right string
---@return function: iterator, returns pairs from,to.
function M.unescaped_pairs(s, left, right)
	local search_from = 1

	return function()
		local match_from = find_next_unescaped(s, left, search_from)
		if not match_from then
			return nil
		end
		local match_to = find_next_unescaped(s, right, match_from + 1)
		if not match_to then
			return nil
		end

		search_from = match_to + 1
		return match_from, match_to
	end
end

function M.aupatescape(s)
	if vim.fn.has("win32") or vim.fn.has("win64") then
		-- windows: replace \ with / for au-pattern.
		s, _ = s:gsub("\\", "/")
	end
	local escaped, _ = s:gsub(",", "\\,")
	return vim.fn.fnameescape(escaped)
end

function M.sanitize(str)
	return str:gsub("%\r", "")
end

return M
