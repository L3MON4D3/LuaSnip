local node_mod = require'node'
local snip_mod = require'snippet'
local util = require'util'

local active_snippet = nil
local next_expand = nil
Ns_id = vim.api.nvim_create_namespace("luasnip")

local function get_active_snip() return active_snippet end

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	for i = 1, #ls.snippets do
		local snip = ls.snippets[i]
		-- if line ends with trigger
		if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
			if snip.condition(unpack(snip.user_args)) then
				local o = vim.deepcopy(snip)
				for j, n in ipairs(snip.nodes) do
					setmetatable(o.nodes[j], getmetatable(n))
				end
				setmetatable(o, getmetatable(snip))
				return o
			end
		end
	end
	return nil
end

local function jump(dir)
	if active_snippet ~= nil then
		local exit = active_snippet:jump(dir)
		if exit then
			active_snippet = active_snippet.parent
		end
		return true
	end
	return false
end

local function expand_or_jumpable()
	next_expand = match_snippet(util.get_current_line_to_cursor())
	return (next_expand ~= nil) or (active_snippet ~= nil)
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	if next_expand ~= nil then
		next_expand:indent(util.get_current_line_to_cursor())

		-- remove snippet-trigger, Cursor at start of future snippet text.
		util.remove_n_before_cur(#next_expand.trigger)

		next_expand:expand()

		next_expand.parent = active_snippet
		active_snippet = next_expand
		next_expand = nil

		return true
	end
	if jump(1) then
		return true
	end
end

local ls = {
	expand_or_jumpable = expand_or_jumpable,
	expand_or_jump = expand_or_jump,
	jump = jump,
	get_active_snip = get_active_snip,
	s = snip_mod.S,
	t = node_mod.T,
	f = node_mod.F,
	i = node_mod.I,
	snippets = {}
}

return ls
