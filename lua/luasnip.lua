local snip_mod = require'nodes.snippet'
local util = require'util.util'

local next_expand = nil
local ls

Luasnip_current_nodes = {}

local function get_active_snip() return snip_mod.get_active() end

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	local match
	if ls.snippets[vim.bo.ft] then
		for _, snip in ipairs(ls.snippets[vim.bo.ft]) do
			match = snip:matches(line)
			if match then
				return match
			end
		end
	end
	for _, snip in ipairs(ls.snippets["all"]) do
		match = snip:matches(line)
		if match then
			return match
		end
	end
	return nil
end

local function jump(dir)
	if Luasnip_current_nodes[vim.api.nvim_get_current_buf()] then
		return Luasnip_current_nodes[vim.api.nvim_get_current_buf()]:jump_from(dir)
	else
		return false
	end
end

local function jumpable(dir)
	local node = Luasnip_current_nodes[vim.api.nvim_get_current_buf()]
	return (node ~= nil and node:jumpable(dir))
end

local function expand_or_jumpable()
	next_expand = match_snippet(util.get_current_line_to_cursor())
	return (next_expand ~= nil) or jumpable(1)
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	if next_expand ~= nil then
		next_expand:trigger_expand(Luasnip_current_nodes[vim.api.nvim_get_current_buf()])
		next_expand = nil
		return true
	else
		local snip = match_snippet(util.get_current_line_to_cursor())
		if snip then
			snip:trigger_expand(Luasnip_current_nodes[vim.api.nvim_get_current_buf()])
			return true
		end
	end
	if jump(1) then
		return true
	end
	return false
end

local function lsp_expand(body)
	local snip = require'util.parser'.parse_snippet({trig = ""}, body)
	snip:trigger_expand(Luasnip_current_nodes[vim.api.nvim_get_current_buf()])
end

local function choice_active()
	return Luasnip_active_choice ~= nil
end

local function change_choice(val)
	return Luasnip_active_choice:change_choice(val)
end

ls = {
	expand_or_jumpable = expand_or_jumpable,
	jumpable = jumpable,
	expand_or_jump = expand_or_jump,
	jump = jump,
	get_active_snip = get_active_snip,
	choice_active = choice_active,
	change_choice = change_choice,
	s = snip_mod.S,
	sn = snip_mod.SN,
	lsp_expand = lsp_expand,
	t = require'nodes.textNode'.T,
	f = require'nodes.functionNode'.F,
	i = require'nodes.insertNode'.I,
	c = require'nodes.choiceNode'.C,
	d = require'nodes.dynamicNode'.D,
	parser = require'util.parser',
	snippets = {}
}

return ls
