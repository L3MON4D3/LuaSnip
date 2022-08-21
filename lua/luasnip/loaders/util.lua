local Path = require("luasnip.util.path")
local util = require("luasnip.util.util")
local session = require("luasnip.session")

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

local function _append(tbl, name, elem)
	if tbl[name] == nil then
		tbl[name] = {}
	end
	table.insert(tbl[name], elem)
end

---Get paths of .snippets files
---@param root string @snippet directory path
---@return table @keys are file types, values are paths
local function get_ft_paths(root, extension)
	local ft_path = {}
	local files, dirs = Path.scandir(root)
	for _, file in ipairs(files) do
		local ft, ext = Path.basename(file, true)
		if ext == extension then
			_append(ft_path, ft, file)
		end
	end
	for _, dir in ipairs(dirs) do
		-- directory-name is ft for snippet-files.
		local ft = vim.fn.fnamemodify(dir, ":t")
		files, _ = Path.scandir(dir)
		for _, file in ipairs(files) do
			if vim.endswith(file, extension) then
				-- produce normalized filenames.
				_append(ft_path, ft, Path.normalize(file))
			end
		end
	end
	return ft_path
end

-- extend table like {lua = {path1}, c = {path1, path2}, ...}, new_paths has the same layout.
local function extend_ft_paths(paths, new_paths)
	for ft, path in pairs(new_paths) do
		if paths[ft] then
			vim.list_extend(paths[ft], path)
		else
			paths[ft] = vim.deepcopy(path)
		end
	end
end

--- Find
---   1. all files that belong to a collection and
---   2. the files from that
---      collection that should actually be loaded.
---@param opts table: straight from `load`/`lazy_load`.
---@param rtp_dirname string: if no path is given in opts, we look for a
--- directory named `rtp_dirname` in the runtimepath.
---@param extension string: extension of valid snippet-files for the given
--- collection (eg `.lua` or `.snippets`)
---@return table: a list of tables, each of the inner tables contains two
--- entries:
--- - collection_paths: ft->files for the entire collection and
--- - load_paths: ft->files for only the files that should be loaded.
--- All produced filenames are normalized, eg. links are resolved and
--- unnecessary . or .. removed.
local function get_load_paths_snipmate_like(opts, rtp_dirname, extension)
	local collections_load_paths = {}

	for _, path in ipairs(normalize_paths(opts.paths, rtp_dirname)) do
		local collection_ft_paths = get_ft_paths(path, extension)

		local load_paths = vim.deepcopy(collection_ft_paths)
		-- remove files for excluded/non-included filetypes here.
		local collection_filter = ft_filter(opts.exclude, opts.include)
		for ft, _ in pairs(load_paths) do
			if not collection_filter(ft) then
				load_paths[ft] = nil
			end
		end

		table.insert(collections_load_paths, {
			collection_paths = collection_ft_paths,
			load_paths = load_paths,
		})
	end

	return collections_load_paths
end

--- Asks (via vim.ui.select) to edit a file that currently provides snippets
---@param ft_files table, map filetype to a number of files.
local function edit_snippet_files(ft_files)
	local fts = util.get_snippet_filetypes()
	vim.ui.select(fts, {
		prompt = "Select filetype:",
	}, function(item, _)
		if item then
			local ft_paths = ft_files[item]
			if ft_paths then
				-- prompt user again if there are multiple files providing this filetype.
				if #ft_paths > 1 then
					vim.ui.select(ft_paths, {
						prompt = "Multiple files for this filetype, choose one:",
					}, function(multi_item)
						if multi_item then
							vim.cmd("edit " .. multi_item)
						end
					end)
				else
					vim.cmd("edit " .. ft_paths[1])
				end
			else
				print("No file for this filetype.")
			end
		end
	end)
end

local function add_opts(opts)
	return {
		override_priority = opts.override_priority,
		default_priority = opts.default_priority,
	}
end

local function get_load_fts(bufnr)
	local fts = session.config.load_ft_func(bufnr)

	return util.redirect_filetypes(fts)
end

return {
	filetypelist_to_set = filetypelist_to_set,
	split_lines = split_lines,
	normalize_paths = normalize_paths,
	ft_filter = ft_filter,
	get_ft_paths = get_ft_paths,
	get_load_paths_snipmate_like = get_load_paths_snipmate_like,
	extend_ft_paths = extend_ft_paths,
	edit_snippet_files = edit_snippet_files,
	add_opts = add_opts,
	get_load_fts = get_load_fts,
}
