local cond_obj = require("luasnip.extras.conditions")

-- use the functions from show as basis and extend/overwrite functions specific for expand here
local M = vim.deepcopy(require("luasnip.extras.conditions.show"))
-----------------------
-- PRESET CONDITIONS --
-----------------------
local function line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end
M.line_begin = cond_obj.make_condition(line_begin)

--- The wordTrig flag will only expand the snippet if
--- the proceeding character is NOT %w or `_`.
--- This is quite useful. The only issue is that the characters
--- on which we negate on hard coded. See here for the actual implementation
--- https://github.com/L3MON4D3/LuaSnip/blob/c9b9a22904c97d0eb69ccb9bab76037838326817/lua/luasnip/nodes/snippet.lua#L827
---
--- As a result, authors willl turn their plain triggers into regexTrig=true
--- triggers and proceed their regex with a negated capture group.
--- The issue is that the capture group on which the pattern matched, although
--- its negated, still expands with the rest of the trigger.
--- So people have worked around that by doing inserting the capture group
--- back into the snippet
--- https://ejmastnak.com/tutorials/vim-latex/luasnip/#after-a
---
--- This is an issue because it can break LuaSnips understanding
--- of parent and child snippets, resulting in broken jump_next() etc.
--- For instance, consider
--- ```text
--- $mbb$
---    ^
--- Cursor is here
--- ```
--- Some latex snippet authors will have their snippet definition
--- for mbb look like s(trig="([^%w])mbb", t("\mathbb{}")
--- The problem is that this consume the leading `$~ character, and even if
--- the snippet re-inserts the `$` back, the parent snippet $$ will be broken.
---
--- I think the character wordTrig=true uses should be customized
--- A condtion seems like the best way to do it
---
--- @param pattern string should be a character class eg `[%w]`
function M.trigger_not_preceded_by(pattern)
	local condition = function(line_to_cursor, matched_trigger)
		local line_to_trigger_len = #line_to_cursor - #matched_trigger
		if line_to_trigger_len == 0 then
			return true
		end
		return not string
			.sub(line_to_cursor, line_to_trigger_len, line_to_trigger_len)
			:match(pattern)
	end
	return cond_obj.make_condition(condition)
end
M.word_trig_condition = M.trigger_not_preceded_by("[%w_]")

return M
