-- Some string processing utility functions
local M = {}

function M.dedent(s)
	local lst = vim.split(s, "\n")
	if #lst > 0 then
		local ind_size = math.huge
		for i, _ in ipairs(lst) do
			local i1, i2 = lst[i]:find("^%s*[^%s]")
			if i1 and i2 < ind_size then
				ind_size = i2
			end
		end
		for i, _ in ipairs(lst) do
			lst[i] = lst[i]:sub(ind_size, -1)
		end
	end
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

return M
