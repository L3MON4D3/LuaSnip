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

-- requires that from and to are within the region of str.
-- str is treated as a 0,0-indexed, and the character at `to` is excluded from
-- the result.
-- `from` may not be before `to`.
function M.multiline_substr(str, from, to)
	local res = {}

	-- include all rows
	for i = from[1], to[1] do
		table.insert(res, str[i+1])
	end

	-- trim text before from and after to.
	-- First trim from behind, that way this works correctly if from and to are
	-- on the same line. If res[1] was trimmed first, we'd have to adjust the
	-- trim-point of `to`.
	res[#res] = res[#res]:sub(1, to[2])
	res[1] = res[1]:sub(from[2]+1)

	return res
end

function M.multiline_upper(str)
	for i, s in ipairs(str) do
		str[i] = s:upper()
	end
end
function M.multiline_lower(str)
	for i, s in ipairs(str) do
		str[i] = s:lower()
	end
end

-- modifies strmod
function M.multiline_append(strmod, strappend)
	strmod[#strmod] = strmod[#strmod] .. strappend[1]
	for i = 2, #strappend do
		table.insert(strmod, strappend[i])
	end
end

-- turn a row+col-offset for a multiline-string (string[]) (where the column is
-- given in utf-codepoints and 0-based) into an offset (in bytes!, 1-based) for
-- the \n-concatenated version of that string.
function M.multiline_to_byte_offset(str, pos)
	if pos[1] < 0 or pos[1]+1 > #str or pos[2] < 0 then
		-- pos is trivially (row negative or beyond str, or col negative)
		-- outside of str, can't represent position in str.
		-- col-wise outside will be determined later, but we want this
		-- precondition for following code.
		return nil
	end

	local byte_pos = 0
	for i = 1, pos[1] do
		-- increase index by full lines, don't forget +1 for \n.
		byte_pos = byte_pos + #str[i]+1
	end

	-- allow positions one beyond the last character for all lines (even the
	-- last line).
	local pos_line_str = str[pos[1]+1] .. "\n"

	if pos[2] >= #pos_line_str then
		-- in this case, pos is outside of the multiline-region.
		return nil
	end
	byte_pos = byte_pos + vim.str_byteindex(pos_line_str, pos[2])

	-- 0- to 1-based columns
	return byte_pos+1
end

-- inverse of multiline_to_byte_offset, 1-based byte to 0,0-based row,column, utf-aware.
function M.byte_to_multiline_offset(str, byte_pos)
	if byte_pos < 0 then
		return nil
	end

	local byte_pos_so_far = 0
	for i, line in ipairs(str) do
		local line_i_end = byte_pos_so_far + #line+1
		if byte_pos <= line_i_end then
			-- byte located in this line, find utf-index.
			local utf16_index = vim.str_utfindex(line .. "\n", byte_pos - byte_pos_so_far-1)
			return {i-1, utf16_index}
		end
		byte_pos_so_far = line_i_end
	end
end

-- string-operations implemented according to
-- https://github.com/microsoft/vscode/blob/71c221c532996c9976405f62bb888283c0cf6545/src/vs/editor/contrib/snippet/browser/snippetParser.ts#L372-L415
-- such that they can be used for snippet-transformations in vscode-snippets.
local function capitalize(str)
	-- uppercase first character.
	return str:gsub("^.", string.upper)
end
local function pascalcase(str)
	local pascalcased = ""
	for match in str:gmatch("[a-zA-Z0-9]+") do
		pascalcased = pascalcased .. capitalize(match)
	end
	return pascalcased
end

M.vscode_string_modifiers = {
	upcase = string.upper,
	downcase = string.lower,
	capitalize = capitalize,
	pascalcase = pascalcase,
	camelcase = function(str)
		-- same as pascalcase, but first character lowercased.
		return pascalcase(str):gsub("^.", string.lower)
	end,
}

return M
