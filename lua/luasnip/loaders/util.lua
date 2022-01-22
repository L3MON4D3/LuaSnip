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

local function split_lines(filestring)
	-- test for used line separator and split accordingly.
	if filestring:find("\r\n") then
		return vim.split(filestring, "\r\n", {plain = true, trimemtpy = false})
	elseif filestring:find("\r") then
		-- both mac and unix-files contain a trailing newline which would lead
		-- to an additional empty line being read (\r, \n _terminate_ lines, they
		-- don't _separate_ them)
		return vim.split(filestring:sub(1, #filestring-1), "\r", {plain = true, trimemtpy = false})
	else
		return vim.split(filestring:sub(1, #filestring-1), "\n", {plain = true, trimemtpy = false})
	end
end

return {
	filetypelist_to_set = filetypelist_to_set,
	split_lines = split_lines
}
