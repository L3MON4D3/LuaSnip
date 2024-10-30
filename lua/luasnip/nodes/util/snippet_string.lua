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

function SnippetString:str()
	local str = ""
	for _, snipstr_or_str in ipairs(self) do
		if snipstr_or_str.snip then
			snipstr_or_str.snip:subtree_do({
				pre = function(node)
					if node.static_text then
						if M.isinstance(node.static_text) then
							str = str .. node.static_text:str()
						else
							str = str .. table.concat(node.static_text, "\n")
						end
					end
				end,
				post = util.nop
			})
		else
			str = str .. snipstr_or_str
		end
	end
	return str
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

function SnippetString:_upper()
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

function SnippetString:upper()
	local cop = self:copy()
	cop:_upper()
	return cop
end

function SnippetString:_lower()
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
	cop:_lower()
	return cop
end

return M
