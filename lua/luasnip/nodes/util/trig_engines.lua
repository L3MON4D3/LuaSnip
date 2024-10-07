local jsregexp_compile_safe = require("luasnip.util.jsregexp")

-- generate nil-opts-instances here, and save them.
-- This is to prevent generating 100s of the exact same function.
local default_match_pattern, default_match_plain, default_match_vim

local function apply_common_opts(line_to_cursor, opts)
	if opts and opts.max_len then
		return line_to_cursor:sub(
			math.max(0, #line_to_cursor - opts.max_len + 1)
		)
	else
		return line_to_cursor
	end
end

-- these functions get the line up to the cursor, the trigger, and then
-- determine whether the trigger matches the current line.
-- If the trigger does not match, the functions shall return nil, otherwise
-- the matching substring and the list of captures (empty table if there aren't
-- any).

local function match_plain(_, opts)
	if opts == nil then
		return default_match_plain
	end

	return function(line_to_cursor, trigger)
		line_to_cursor = apply_common_opts(line_to_cursor, opts)
		if
			line_to_cursor:sub(#line_to_cursor - #trigger + 1, #line_to_cursor)
			== trigger
		then
			-- no captures for plain trigger.
			return trigger, {}
		else
			return nil
		end
	end
end
default_match_plain = match_plain(nil, {})

local function match_pattern(_, opts)
	if opts == nil then
		return default_match_pattern
	end

	return function(line_to_cursor, trigger)
		line_to_cursor = apply_common_opts(line_to_cursor, opts)

		-- look for match which ends at the cursor.
		-- put all results into a list, there might be many capture-groups.
		local find_res = { line_to_cursor:find(trigger .. "$") }

		if #find_res > 0 then
			-- if there is a match, determine matching string, and the
			-- capture-groups.
			local captures = {}
			-- find_res[1] is `from`, find_res[2] is `to` (which we already know
			-- anyway).
			local from = find_res[1]
			local match = line_to_cursor:sub(from, #line_to_cursor)
			-- collect capture-groups.
			for i = 3, #find_res do
				captures[i - 2] = find_res[i]
			end
			return match, captures
		else
			return nil
		end
	end
end
default_match_pattern = match_pattern(nil, {})

local ecma_engine
if jsregexp_compile_safe then
	ecma_engine = function(trig, opts)
		local trig_compiled, err_maybe = jsregexp_compile_safe(trig .. "$", "")
		if not trig_compiled then
			error(("Error while compiling regex: %s"):format(err_maybe))
		end

		return function(line_to_cursor, _)
			line_to_cursor = apply_common_opts(line_to_cursor, opts)

			-- get first (very likely only, since we appended the "$") match.
			local match = trig_compiled(line_to_cursor)[1]
			if match then
				-- return full match, and all groups.
				return line_to_cursor:sub(match.begin_ind), match.groups
			else
				return nil
			end
		end
	end
else
	ecma_engine = function(x, opts)
		return match_plain(x, opts)
	end
end

local function match_vim(_, opts)
	if opts == nil then
		return default_match_vim
	end

	return function(line_to_cursor, trigger)
		line_to_cursor = apply_common_opts(line_to_cursor, opts)

		local matchlist = vim.fn.matchlist(line_to_cursor, trigger .. "$")
		if #matchlist > 0 then
			local groups = {}
			for i = 2, 10 do
				-- PROBLEM: vim does not differentiate between an empty ("")
				-- and a missing capture.
				-- Since we need to differentiate between the two (Check `:h
				-- luasnip-variables-lsp-variables`), we assume, here, that an
				-- empty string is an unmatched group.
				groups[i - 1] = matchlist[i] ~= "" and matchlist[i] or nil
			end
			return matchlist[1], groups
		else
			return nil
		end
	end
end
default_match_vim = match_vim(nil, {})

return {
	plain = match_plain,
	pattern = match_pattern,
	ecma = ecma_engine,
	vim = match_vim,
}
