local ls = require("luasnip")
local cache = require("luasnip.loaders._caches").snipmate
local util = require("luasnip.util.util")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local session = require("luasnip.session")

local function parse_snipmate(buffer, filename)
	local snippet = {}
	local extends = {}

	---@type string[]
	local lines = loader_util.split_lines(buffer)
	local i = 1

	local function _parse()
		local line = lines[i]
		local prefix, description = line:match([[^snippet%s+(%S+)%s*(.*)]])
		local body = {}

		i = i + 1
		---@type number
		local indent

		while i <= #lines do
			line = lines[i]
			if line:find("^%s+") then
				if not indent then
					indent = #line:match("^%s+")
				end
				line = line:sub(indent + 1)
				line = line:gsub("${VISUAL}", "${TM_SELECTED_TEXT}")
			elseif line ~= "" then
				break
			end
			table.insert(body, line)
			i = i + 1
		end

		body = table.concat(body, "\n")
		local snip = ls.parser.parse_snippet({
			trig = prefix,
			dscr = description,
			wordTrig = true,
		}, body)
		table.insert(snippet, snip)
	end

	while i <= #lines do
		local line = lines[i]
		if vim.startswith(line, "snippet") then
			_parse()
		elseif vim.startswith(line, "extends") then
			local scopes = vim.split(vim.trim(line:sub(8)), "[,%s]+")
			vim.list_extend(extends, scopes)
			i = i + 1
		elseif vim.startswith(line, "#") or line:find("^%s*$") then
			-- comment and blank line
			i = i + 1
		else
			error(("invalid line in %s: %s"):format(filename, i))
		end
	end

	return snippet, extends
end

local function load_snippet_file(lang, path)
	if not Path.exists(path) then
		return
	end

	Path.async_read_file(
		path,
		vim.schedule_wrap(function(buffer)
			local snippet, extends = parse_snipmate(buffer, path)
			if not snippet then
				return
			end
			table.insert(extends, lang)
			for _, ft in ipairs(extends) do
				local lang_snips = ls.snippets[ft] or {}
				ls.snippets[ft] = vim.list_extend(lang_snips, snippet)
				session.latest_load_ft = ft
				vim.cmd("do User LuasnipSnippetsAdded")
			end
		end)
	)
end

local function filter(exclude, include)
	vim.validate({
		exclude = { exclude, "table" },
		include = { include, "table", true },
	})

	exclude = loader_util.filetypelist_to_set(exclude)
	include = loader_util.filetypelist_to_set(include)

	return function(lang)
		if exclude[lang] then
			return false
		end
		if include == nil or include[lang] then
			return true
		end
	end
end

local function get_paths(root)
	local ret = {}
	local files = Path.scandir(root, "file", true)
	for _, file in ipairs(files) do
		local name, ext = Path.basename(file, true)
		if ext == "snippets" then
			table.insert(ret, { path = Path.join(root, file), ft = name })
		end
	end
	local dirs = Path.scandir(root, "directory")
	for _, dir in ipairs(dirs) do
		local name = dir
		files = Path.scandir(Path.join(root, dir), "file")
		for _, file in ipairs(files) do
			if vim.endswith(file, ".snippets") then
				table.insert(
					ret,
					{ path = Path.join(root, dir, file), ft = name }
				)
			end
		end
	end
	return ret
end

local function load_snippet_folder(root, opts)
	local paths = get_paths(root)
	local ft_filter = filter(opts.exclude, opts.include)

	for _, v in ipairs(paths) do
		local path, ft = v.path, v.ft
		if ft_filter(ft) then
			load_snippet_file(ft, path)
		end
	end
end

local M = {}

function M.load(opts)
	opts = opts or {}
	opts.exclude = opts.exclude or {}

	if not opts.paths then
		opts.paths = vim.api.nvim_get_runtime_file("snippets", true)
	elseif type(opts.paths) == "string" then
		opts.paths = vim.split(opts.paths, ",")
	end

	opts.paths = vim.tbl_map(Path.expand, opts.paths)
	opts.paths = util.deduplicate(opts.paths)

	for _, path in ipairs(opts.paths) do
		load_snippet_folder(path, opts)
	end
end

function M._lazyload()
	local fts = util.get_snippet_filetypes()
	for _, ft in ipairs(fts) do
		if not cache.lazy_loaded_ft[ft] then
			cache.lazy_loaded_ft[ft] = true
			M.load({ paths = cache.lazy_load_paths, include = { ft } })
		end
	end
end

function M.lazy_load(opts)
	opts = opts or {}

	if not opts.paths then
		opts.paths = vim.api.nvim_get_runtime_file("snippets", true)
	elseif type(opts.paths) == "string" then
		opts.paths = vim.split(opts.paths, ",")
	end
	vim.list_extend(cache.lazy_load_paths, opts.paths)

	cache.lazy_load_paths = util.deduplicate(cache.lazy_load_paths)

	vim.cmd([[
    augroup _luasnip_snipmate_lazy_load
        au!
        au BufWinEnter,FileType * lua require("luasnip.loaders.from_snipmate")._lazyload()
        au User LuasnipCleanup lua require("luasnip.loaders._caches").snipmate.clean()
    augroup END
    ]])
end

return M
