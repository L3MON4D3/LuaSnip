local snip_mod = require("luasnip.nodes.snippet")
local util = require("luasnip.util.util")

local next_expand = nil
local ls

Luasnip_current_nodes = {}

local function get_active_snip()
return snip_mod.get_active()
end

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

local function get_context(snip)
	return {
		name = snip.name,
		trigger = snip.trigger,
		description = snip.dscr,
		wordTrig = snip.wordTrig and true or false,
		regTrig = snip.regTrig and true or false,
	}
end

local function available()
	local res = { [vim.bo.ft] = {}, all = {} }
	if ls.snippets[vim.bo.ft] then
		for _, snip in ipairs(ls.snippets[vim.bo.ft]) do
			table.insert(res[vim.bo.ft], get_context(snip))
		end
	end
	for _, snip in ipairs(ls.snippets["all"]) do
		table.insert(res.all, get_context(snip))
	end
	return res
end

local function jump(dir)
	if Luasnip_current_nodes[vim.api.nvim_get_current_buf()] then
		return Luasnip_current_nodes[vim.api.nvim_get_current_buf()]:jump_from(
			dir
		)
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
		next_expand:trigger_expand(
			Luasnip_current_nodes[vim.api.nvim_get_current_buf()]
		)
		next_expand = nil
		return true
	else
		local snip = match_snippet(util.get_current_line_to_cursor())
		if snip then
			snip:trigger_expand(
				Luasnip_current_nodes[vim.api.nvim_get_current_buf()]
			)
			return true
		end
	end
	if jump(1) then
		return true
	end
	return false
end

local function lsp_expand(body)
	local snip = ls.parser.parse_snippet({ trig = "" }, body)
	snip:trigger_expand(Luasnip_current_nodes[vim.api.nvim_get_current_buf()])
end

local function choice_active()
	return Luasnip_active_choice ~= nil
end

local function change_choice(val)
	return Luasnip_active_choice:change_choice(val)
end

local function unlink_current()
	local node = Luasnip_current_nodes[vim.api.nvim_get_current_buf()]
	if not node then
		print("No active Snippet")
		return
	end
	local user_expanded_snip = node.parent
	-- find 'outer' snippet.
	while user_expanded_snip.parent do
		user_expanded_snip = user_expanded_snip.parent
	end
	user_expanded_snip:remove_from_jumplist()
end

local function active_update_dependents()
	local active = Luasnip_current_nodes[vim.api.nvim_get_current_buf()]
	-- special case for startNode, still gets triggered somehow, TODO.
	if active and active.pos ~= -1 and active.dependents ~= {} then
		-- Save cursor-pos to restore later.
		local cur = util.get_cursor_0ind()
		local cur_mark = vim.api.nvim_buf_set_extmark(
			0,
			Luasnip_ns_id,
			cur[1],
			cur[2],
			{ right_gravity = false }
		)

		active:update_dependents()
		-- update all parent's dependents.
		local parent = active.parent
		while parent do
			parent:update_dependents()
			parent = parent.parent
		end
		-- 'restore' orientation of extmarks, may have been changed by some set_text or similar.
		active.parent:enter_node(active.indx)

		-- Don't account for utf, nvim_win_set_cursor doesn't either.
		cur = vim.api.nvim_buf_get_extmark_by_id(
			0,
			Luasnip_ns_id,
			cur_mark,
			{ details = false }
		)
		util.set_cursor_0ind(cur)
	end
end

ls = {
	expand_or_jumpable = expand_or_jumpable,
	jumpable = jumpable,
	expand_or_jump = expand_or_jump,
	jump = jump,
	get_active_snip = get_active_snip,
	choice_active = choice_active,
	change_choice = change_choice,
	unlink_current = unlink_current,
	lsp_expand = lsp_expand,
	active_update_dependents = active_update_dependents,
	available = available,
	s = snip_mod.S,
	sn = snip_mod.SN,
	t = require("luasnip.nodes.textNode").T,
	f = require("luasnip.nodes.functionNode").F,
	i = require("luasnip.nodes.insertNode").I,
	c = require("luasnip.nodes.choiceNode").C,
	d = require("luasnip.nodes.dynamicNode").D,
	snippet = snip_mod.S,
	snippet_node = snip_mod.SN,
	text_node = require("luasnip.nodes.textNode").T,
	function_node = require("luasnip.nodes.functionNode").F,
	insert_node = require("luasnip.nodes.insertNode").I,
	choice_node = require("luasnip.nodes.choiceNode").C,
	dynamic_node = require("luasnip.nodes.dynamicNode").D,
	parser = require("luasnip.util.parser"),
	config = require("luasnip.config"),
	snippets = { all = {} },
}

return ls
