-- Minimal parser combinator,
-- only for internal use so not exposed elsewhere nor documented in the oficial doc
--
local M = {}

-- Consumes strings matching a pattern, generates the matched string
function M.pattern(pat)
	return function(text, pos)
		local s, e = text:find(pat, pos)

		if s then
			local v = text:sub(s, e)
			return true, v, pos + #v
		else
			return false, nil, pos
		end
	end
end

-- Matches whatever `p matches and generates  whatever p generates after
-- transforming it with `f
function M.map(p, f)
	return function(text, pos)
		local succ, val, new_pos = p(text, pos)
		if succ then
			return true, f(val), new_pos
		end
		return false, nil, pos
	end
end

-- Matches and generates the same as the first of it's children that matches something
function M.any(...)
	local parsers = { ... }
	return function(text, pos)
		for _, p in ipairs(parsers) do
			local succ, val, new_pos = p(text, pos)
			if succ then
				return true, val, new_pos
			end
		end
		return false, nil, pos
	end
end

-- Matches all what its children do in sequence, generates a table of its children generations
function M.seq(...)
	local parsers = { ... }
	return function(text, pos)
		local original_pos = pos
		local values = {}
		for _, p in ipairs(parsers) do
			local succ, val, new_pos = p(text, pos)
			pos = new_pos
			if not succ then
				return false, nil, original_pos
			end
			table.insert(values, val)
		end
		return true, values, pos
	end
end

-- Matches cero or more times what it child do in sequence, generates a table with those generations
function M.star(p)
	return function(text, pos)
		local len = #text
		local values = {}

		while pos <= len do
			local succ, val, new_pos = p(text, pos)
			if succ then
				pos = new_pos
				table.insert(values, val)
			else
				break
			end
		end
		return #values > 0, values, pos
	end
end

-- Consumes a literal string, does not generates
function M.literal(t)
	return function(text, pos)
		if text:sub(pos, pos + #t - 1) == t then
			return true, nil, pos + #t
		else
			return false, text:sub(pos, pos + #t), pos + #t
		end
	end
end

return M
