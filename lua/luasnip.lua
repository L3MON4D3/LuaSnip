local node_mod = require'node'
local snip_mod = require'snippet'
local util = require'util'

local next_expand = nil

local function get_active_snip() return snip_mod.get_active() end

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	if ls.snippets[vim.bo.ft] then
		for _, snip in ipairs(ls.snippets[vim.bo.ft]) do
			-- if line ends with trigger
			if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
				if snip.condition(unpack(snip.user_args)) then
					return snip:copy()
				end
			end
		end
	end
	for _, snip in ipairs(ls.snippets["all"]) do
		-- if line ends with trigger
		if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
			if snip.condition(unpack(snip.user_args)) then
				return snip:copy()
			end
		end
	end
	return nil
end

local function jump(dir)
	if Luasnip_active_snippet ~= nil then
		Luasnip_active_snippet:jump(dir)
		return true
	end
	return false
end

local function expand_or_jumpable()
	next_expand = match_snippet(util.get_current_line_to_cursor())
	return (next_expand ~= nil) or (Luasnip_active_snippet ~= nil)
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	if next_expand ~= nil then
		-- remove snippet-trigger, Cursor at start of future snippet text.
		util.remove_n_before_cur(#next_expand.trigger)

		next_expand:put_initial()

		next_expand:input_enter()
		next_expand = nil

		return true
	end
	if jump(1) then
		return true
	end
end

local function choice_active()
	return Luasnip_active_choice ~= nil
end

local function change_choice(val)
	return Luasnip_active_choice:change_choice(val)
end

local function confirm_choice()
	Luasnip_active_snippet:input_enter()
end

local ls = {
	expand_or_jumpable = expand_or_jumpable,
	expand_or_jump = expand_or_jump,
	jump = jump,
	get_active_snip = get_active_snip,
	choice_active = choice_active,
	change_choice = change_choice,
	confirm_choice = confirm_choice,
	s = snip_mod.S,
	sn = snip_mod.SN,
	t = node_mod.T,
	f = node_mod.F,
	i = node_mod.I,
	c = node_mod.C,
	snippets = {}
}

return ls
