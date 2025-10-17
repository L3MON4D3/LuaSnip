local str_util = require("luasnip.util.str")
local util = require("luasnip.util.util")

---@class SnippetString
local SnippetString = {}
local SnippetString_mt = {
	__index = SnippetString,
}

local M = {}

---Create new SnippetString.
---@param initial_str string[]?, optional initial multiline string.
---@return SnippetString
function M.new(initial_str)
	local o = {initial_str and table.concat(initial_str, "\n")}
	return setmetatable(o, SnippetString_mt)
end

function M.isinstance(o)
	return getmetatable(o) == SnippetString_mt
end

function SnippetString:append_snip(snip)
	table.insert(self, {snip = snip})
end
function SnippetString:append_text(str)
	table.insert(self, table.concat(str, "\n"))
end

-- compute table mapping
-- * each snippet in this snipstr (including nested) to its string-content
-- * each component in the snippet_string (including nested) to the text-index
--   of its first character.
-- * the string of each nested snippetString.
local function gen_snipstr_map(self, map, from_offset)
	map[self] = {}

	local str = ""
	for i, v in ipairs(self) do
		map[self][i] = from_offset + #str
		if v.snip then
			local snip_str = ""
			v.snip:subtree_do({
				pre = function(node)
					if node.static_text then
						if M.isinstance(node.static_text) then
							local nested_str = gen_snipstr_map(node.static_text, map, from_offset + #str + #snip_str)
							snip_str = snip_str .. nested_str
						else
							snip_str = snip_str .. table.concat(node.static_text, "\n")
						end
					end
				end,
				post = util.nop
			})
			map[v.snip] = snip_str
			str = str .. snip_str
		else
			str = str .. v
		end
	end
	map[self].str = str
	return str
end

function SnippetString:str()
	-- if too slow, generate another version of that function without the
	-- snipstr_map-calls.
	return gen_snipstr_map(self, {}, 1)
end
SnippetString_mt.__tostring = SnippetString.str

function SnippetString:indent(indentstr)
	for k, snipstr_or_str in ipairs(self) do
		if snipstr_or_str.snip then
			snipstr_or_str.snip:indent(indentstr)
		else
			local str_tmp = vim.split(snipstr_or_str, "\n")
			util.indent(str_tmp, indentstr)
			self[k] = table.concat(str_tmp, "\n")
		end
	end
end

function SnippetString:expand_tabs(tabwidth, indenstrlen)
	for k, snipstr_or_str in ipairs(self) do
		if snipstr_or_str.snip then
			snipstr_or_str.snip:expand_tabs(tabwidth, indenstrlen)
		else
			local str_tmp = vim.split(snipstr_or_str, "\n")
			util.expand_tabs(str_tmp, tabwidth, indenstrlen)
			self[k] = table.concat(str_tmp, "\n")
		end
	end
end

function SnippetString:iter_snippets()
	local i = 1
	return function()
		-- find the next snippet.
		while self[i] and (not self[i].snip) do
			i = i+1
		end
		local res = self[i] and self[i].snip
		i = i+1
		return res
	end
end

-- pos is modified to reflect the new cursor-position!
function SnippetString:put(pos)
	for _, snipstr_or_str in ipairs(self) do
		if snipstr_or_str.snip then
			snipstr_or_str.snip:put(pos)
		else
			util.put(vim.split(snipstr_or_str, "\n"), pos)
		end
	end
end

function SnippetString:copy()
	-- on 0.7 vim.deepcopy does not behave correctly => have to manually copy.
	return setmetatable(vim.tbl_map(function(snipstr_or_str)
		if snipstr_or_str.snip then
			local snip = snipstr_or_str.snip

			-- remove associations with objects beyond this snippet.
			-- This is so we can easily deepcopy it without copying too much data.
			-- We could also do this copy in 
			local prevprev = snip.prev.prev
			local i0next = snip.insert_nodes[0].next
			local parentnode = snip.parent_node

			snip.prev.prev = nil
			snip.insert_nodes[0].next = nil
			snip.parent_node = nil

			local snipcop = snip:copy()

			snip.prev.prev = prevprev
			snip.insert_nodes[0].next = i0next
			snip.parent_node = parentnode


			-- bring into inactive mode, so that we will jump into it correctly when it
			-- is expanded again.
			snipcop:subtree_do({
				pre = function(node)
					node.mark:invalidate()
				end,
				post = util.nop,
				do_child_snippets = true
			})
			-- snippet may have been active (for example if captured as an
			-- argnode), so finally exit here (so we can put_initial it again!)
			snipcop:exit()

			return {snip = snipcop}
		else
			return snipstr_or_str
		end
	end, self), SnippetString_mt)
end

-- copy without copying snippets.
function SnippetString:flatcopy()
	local res = {}
	for i, v in ipairs(self) do
		res[i] = util.shallow_copy(v)
	end
	return setmetatable(res, SnippetString_mt)
end

-- where o is string, string[] or SnippetString.
local function to_snippetstring(o)
	if type(o) == "string" then
		return M.new({o})
	elseif getmetatable(o) == SnippetString_mt then
		return o
	else
		return M.new(o)
	end
end

function SnippetString.concat(a, b)
	a = to_snippetstring(a):flatcopy()
	b = to_snippetstring(b):flatcopy()
	vim.list_extend(a, b)

	return a
end
SnippetString_mt.__concat = SnippetString.concat

-- for generic string-operations: we can apply them _and_ keep the snippet as
-- long as a change to the string does not span over extmarks! We need to verify
-- this somehow, and can do this by storing the positions where one extmark ends
-- and another begins in some list or table which is quickly queried.
-- Since all string-operations work with simple strings and not the
-- string-tables we have here usually, we should also convert {"a", "b"} to
-- "a\nb". This also simplifies storing the positions where some node ends, and
-- is much better than converting all the time when a string-operation is
-- involved.

-- only call after it's clear that char_i is contained in self.
local function find(self, start_i, i_inc, char_i, snipstr_map)
	local i = start_i
	while true do
		local v = self[i]
		local current_str_from = snipstr_map[self][i]
		if not v then
			-- leave in for now, no endless loops while testing :D
			error("huh??")
		end
		local v_str
		if v.snip then
			v_str = snipstr_map[v.snip]
		else
			v_str = v
		end

		local current_str_to = current_str_from + #v_str-1
		if char_i >= current_str_from and char_i <= current_str_to then
			return i
		end

		i = i + i_inc
	end
end

local function nodetext_len(node, snipstr_map)
	if not node.static_text then
		return 0
	end

	if M.isinstance(node.static_text) then
		return #snipstr_map[node.static_text].str
	else
		-- +1 for each newline.
		local len = #node.static_text-1
		for _, v in ipairs(node.static_text) do
			len = len + #v
		end
		return len
	end
end

-- replacements may not be zero-width!
local function _replace(self, replacements, snipstr_map)
	-- first character of currently-looked-at text.
	local v_i_search_from = #self

	for i = #replacements, 1, -1 do
		local repl = replacements[i]

		local v_i_to = find(self, v_i_search_from, -1 , repl.to, snipstr_map)
		local v_i_from = find(self, v_i_to, -1, repl.from, snipstr_map)

		-- next range may begin in v_i_from, before the currently inserted
		-- one.
		v_i_search_from = v_i_from

		-- first characters of v_from and v_to respectively.
		local v_from_from = snipstr_map[self][v_i_from]
		local v_to_from = snipstr_map[self][v_i_to]
		local _, repl_in_node = nil, false

		if v_i_from == v_i_to and self[v_i_from].snip then
			local snip = self[v_i_from].snip
			local node_from = v_from_from

			-- will probably always error, res is true if the substitution
			-- could be done, false if repl spans multiple nodes.
			_, repl_in_node = pcall(snip.subtree_do, snip, {
				pre = function(node)
					local node_len = nodetext_len(node, snipstr_map)
					if node_len > 0 then
						local node_relative_repl_from = repl.from - node_from+1
						local node_relative_repl_to = repl.to - node_from+1

						if node_relative_repl_from >= 1 and node_relative_repl_from <= node_len then
							if node_relative_repl_to <= node_len then
								if M.isinstance(node.static_text) then
									-- node contains a snippetString, recurse!
									-- since we only check string-positions via
									-- snipstr_map, we don't even have to
									-- modify repl to be defined based on the
									-- other snippetString. (ie. shift from and to)
									_replace(node.static_text, {repl}, snipstr_map)
								else
									-- simply manipulate the node-static-text
									-- manually.
									--
									-- we don't need to update the snipstr_map
									-- because even if this same node or same
									-- snippet contains another range (which is
									-- the only data in snipstr_map we may
									-- access that is inaccurate), the queries
									-- will still be answered correctly.
									local str = table.concat(node.static_text, "\n")
									node.static_text = vim.split(
										str:sub(1, node_relative_repl_from-1) .. repl.str .. str:sub(node_relative_repl_to+1), "\n")
								end
								-- update string in snipstr_map.
								snipstr_map[snip] = snipstr_map[snip]:sub(1, repl.from - v_from_from-1) .. repl.str .. snipstr_map[snip]:sub(repl.to - v_to_from+1)
								error(true)
							else
								-- range begins in, but ends outside this node
								-- => snippet cannot be preserved.
								-- Replace it with its static text and do the
								-- replacement on that.
								error(false)
							end
						end
						node_from = node_from + node_len
					end
				end,
				post = util.nop
			})
		end
		-- in lieu of `continue`, we need this bool to check whether we did a replacement yet.
		if not repl_in_node then
			local from_str = self[v_i_from].snip and snipstr_map[self[v_i_from].snip] or self[v_i_from]
			local to_str = self[v_i_to].snip and snipstr_map[self[v_i_to].snip] or self[v_i_to]

			-- +1 to get the char of to, +1 to start beyond it.
			self[v_i_from] = from_str:sub(1, repl.from - v_from_from) .. repl.str .. to_str:sub(repl.to - v_to_from+1+1)
			-- start-position of string has to be updated.
			snipstr_map[self][v_i_from] = v_from_from
		end
	end
end

-- replacements may not be zero-width!
local function replace(self, replacements)
	local snipstr_map = {}
	gen_snipstr_map(self, snipstr_map, 1)
	_replace(self, replacements, snipstr_map)
end

local function upper(self)
	for i, v in ipairs(self) do
		if v.snip then
			v.snip:subtree_do({
				pre = function(node)
					if node.static_text then
						if M.isinstance(node.static_text) then
							node.static_text:_upper()
						else
							str_util.multiline_upper(node.static_text)
						end
					end
				end,
				post = util.nop
			})
		else
			self[i] = v:upper()
		end
	end
end

local function lower(self)
	for i, v in ipairs(self) do
		if v.snip then
			v.snip:subtree_do({
				pre = function(node)
					if node.static_text then
						if M.isinstance(node.static_text) then
							node.static_text:_lower()
						else
							str_util.multiline_lower(node.static_text)
						end
					end
				end,
				post = util.nop
			})
		else
			self[i] = v:lower()
		end
	end
end

function SnippetString:lower()
	local cop = self:copy()
	lower(cop)
	return cop
end
function SnippetString:upper()
	local cop = self:copy()
	upper(cop)
	return cop
end

-- gsub will preserve snippets as long as a substituted region does not overlap
-- more than one node.
-- gsub will ignore zero-length matches. In these cases, it becomes less easy
-- to define the association of new string -> static_text it should be
-- associated with, so these are ignored (until a sensible behaviour is clear
-- (maybe respect rgrav behaviour? does not seem useful)).
-- Also, it should be straightforward to circumvent this by doing something
-- like :gsub("(.)", "%1_") or :gsub("(.)", "_%1") to choose the "side" where a
-- new char is inserted,
function SnippetString:gsub(pattern, repl)
	self = self:copy()

	local find_from = 1
	local str = self:str()
	local replacements = {}
	while true do
		local match_from, match_to = str:find(pattern, find_from)
		if not match_from then
			break
		end
		-- only allow matches that are not empty.
		if match_from <= match_to then
			table.insert(replacements, {
				from = match_from,
				to = match_to,
				str = str:sub(match_from, match_to):gsub(pattern, repl)
			})
		end
		find_from = match_to + 1
	end
	replace(self, replacements)

	return self
end

return M
