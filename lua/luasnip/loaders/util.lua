local session = require("luasnip.session")

local function filetypelist_to_set(list)
	vim.validate({ list = { list, "table", true } })
	if not list then
		return list
	end
	local out = {}
	for _, ft in ipairs(list) do
		-- include redirected filetypes.
		for _, resolved_ft in ipairs(session.ft_redirect[ft]) do
			out[resolved_ft] = true
		end
	end
	return out
end

return {
	filetypelist_to_set = filetypelist_to_set,
}
