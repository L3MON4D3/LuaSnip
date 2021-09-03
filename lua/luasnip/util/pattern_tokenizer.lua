local is_class = {
	a = true,
	c = true,
	d = true,
	l = true,
	p = true,
	s = true,
	u = true,
	w = true,
	x = true,
	z = true,
	-- and uppercase versions.
	A = true,
	C = true,
	D = true,
	L = true,
	P = true,
	S = true,
	U = true,
	W = true,
	X = true,
	Z = true,
	-- all others false.
}

local is_rep_mod = {
	["+"] = true,
	["*"] = true,
	["-"] = true,
	["?"] = true,
}

local function is_escaped(text, indx)
	local count = 0
	for i = indx - 1, 1, -1 do
		if string.sub(text, i, i) == "%" then
			count = count + 1
		else
			break
		end
	end
	return count % 2 == 1
end

local function charset_end_indx(string, start_indx)
	-- set plain
	local indx = string:find("]", start_indx, true)
	-- find unescaped ']'
	while indx and is_escaped(string, indx) do
		indx = string:find("]", indx + 1, true)
	end
	return indx
end

return {
	tokenize = function(pattern)
		local indx = 1
		local current_text = ""
		local tokens = {}
		-- assume the pattern starts with text (as opposed to eg. a character
		-- class), worst-case an empty textNode is (unnecessarily) inserted at
		-- the beginning.
		local is_text = true
		while indx <= #pattern do
			local next_indx
			local next_text
			local next_is_text
			-- for some atoms *,+,-,? are not applicable, ignore them.
			local repeatable = true
			local char = pattern:sub(indx, indx)
			if char == "%" then
				if pattern:sub(indx + 1, indx + 1) == "b" then
					-- %b seems to consume exactly the next two chars literally.
					next_is_text = false
					next_indx = indx + 4
					repeatable = false
				elseif is_class[pattern:sub(indx + 1, indx + 1)] then
					next_is_text = false
					next_indx = indx + 2
				else
					-- not a class, just an escaped character.
					next_is_text = true
					next_indx = indx + 2
					-- only append escaped char, not '%'.
				end
			elseif char == "." then
				next_is_text = false
				next_indx = indx + 1
			elseif char == "[" then
				next_is_text = false
				-- if not found, just exit loop now, pattern is malformed.
				next_indx = (charset_end_indx(pattern, indx) or #pattern) + 1
			elseif
				char == "("
				or char == ")"
				or (char == "^" and indx == 1)
			then
				-- ^ is interpreted literally if not at beginning.
				-- $ will always be interpreted literally in triggers.

				-- remove ( and ) from text.
				-- keep text or no-text active.
				next_is_text = is_text
				-- increase indx to exclude ( from tokens.
				indx = indx + 1
				next_indx = indx
				-- cannot repeat group.
				repeatable = false
			else
				next_is_text = true
				next_indx = indx + 1
			end

			if repeatable and is_rep_mod[pattern:sub(next_indx, next_indx)] then
				next_indx = next_indx + 1
				next_is_text = false
			end

			next_text = pattern:sub(indx, next_indx - 1)

			-- check if this token is still the same as the previous.
			if next_is_text == is_text then
				current_text = current_text .. next_text
			else
				tokens[#tokens + 1] = current_text
				current_text = next_text
			end

			indx = next_indx
			is_text = next_is_text
		end

		-- add last part, would normally be added at the end of the loop.
		tokens[#tokens + 1] = current_text
		return tokens
	end,
}
