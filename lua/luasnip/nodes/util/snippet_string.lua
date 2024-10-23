local str_util = require("luasnip.util.str")

local SnippetString = {}
local SnippetString_mt = {
	__index = SnippetString,
	__tostring = SnippetString.tostring
}

local M = {}

function M.new()
	local o = {}
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

return M
