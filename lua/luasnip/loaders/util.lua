local Path = require("luasnip.util.path")
local util = require("luasnip.util.util")

local function filetypelist_to_set(list)
	vim.validate({ list = { list, "table", true } })
	if not list then
		return list
	end
	local out = {}
	for _, ft in ipairs(list) do
		out[ft] = true
	end
	return out
end

local function split_lines(filestring)
	local newline_code
	if vim.endswith(filestring, "\r\n") then -- dos
		newline_code = "\r\n"
	elseif vim.endswith(filestring, "\r") then -- mac
		-- both mac and unix-files contain a trailing newline which would lead
		-- to an additional empty line being read (\r, \n _terminate_ lines, they
		-- don't _separate_ them)
		newline_code = "\r"
		filestring = filestring:sub(1, -2)
	elseif vim.endswith(filestring, "\n") then -- unix
		newline_code = "\n"
		filestring = filestring:sub(1, -2)
	else -- dos
		newline_code = "\r\n"
	end
	return vim.split(
		filestring,
		newline_code,
		{ plain = true, trimemtpy = false }
	)
end

local function normalize_paths(paths, rtp_dirname)
	if not paths then
		paths = vim.api.nvim_get_runtime_file(rtp_dirname, true)
	elseif type(paths) == "string" then
		paths = vim.split(paths, ",")
	end

	paths = vim.tbl_map(Path.expand, paths)
	paths = util.deduplicate(paths)

	return paths
end

local function ft_filter(exclude, include)
	exclude = filetypelist_to_set(exclude)
	include = filetypelist_to_set(include)

	return function(lang)
		if exclude and exclude[lang] then
			return false
		end
		if include == nil or include[lang] then
			return true
		end
	end
end

return {
	filetypelist_to_set = filetypelist_to_set,
	split_lines = split_lines,
	normalize_paths = normalize_paths,
	ft_filter = ft_filter,
}
