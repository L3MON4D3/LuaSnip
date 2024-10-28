local str_util = require("luasnip.util.str")
local util = require("luasnip.util.util")

---@class SnippetString
local SnippetString = {}
local SnippetString_mt = {
	__index = SnippetString,
	__tostring = SnippetString.str
}

local M = {}

---Create new SnippetString.
---@param initial_str string[]?, optional initial multiline string.
---@return SnippetString
function M.new(initial_str)
	local o = {initial_str}
	return setmetatable(o, SnippetString_mt)
end

function SnippetString:append_snip(snip, str)
	table.insert(self, {snip = snip, str = str})
end
function SnippetString:append_text(str)
	table.insert(self, str)
end
function SnippetString:str()
	local str = {""}
	for _, snipstr_or_str in ipairs(self) do
		str_util.multiline_append(str, snipstr_or_str.str and snipstr_or_str.str or snipstr_or_str)
	end
	return str
end

function SnippetString:indent(indentstr)
	for _, snipstr_or_str in ipairs(self) do
		if snipstr_or_str.snip then
			snipstr_or_str.snip:indent(indentstr)
			util.indent(snipstr_or_str.str, indentstr)
		else
			util.indent(snipstr_or_str, indentstr)
		end
	end
end

function SnippetString:expand_tabs(tabwidth, indenstrlen)
	for _, snipstr_or_str in ipairs(self) do
		if snipstr_or_str.snip then
			snipstr_or_str.snip:expand_tabs(tabwidth, indenstrlen)
			util.expand_tabs(snipstr_or_str.str, tabwidth, indenstrlen)
		else
			util.expand_tabs(snipstr_or_str, tabwidth, indenstrlen)
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
			util.put(snipstr_or_str, pos)
		end
	end
end

return M
