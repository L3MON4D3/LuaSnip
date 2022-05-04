local ls = require("luasnip")
local cache = require("luasnip.loaders._caches").snipmate
local util = require("luasnip.util.util")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local session = require("luasnip.session")
local sp = require("luasnip.nodes.snippetProxy")

local function parse_snipmate(buffer, filename)
	-- could also be separate variables, but easier to access this way.
	local snippets = {
		snippet = {},
		autosnippet = {},
	}
	local extends = {}

	---@type string[]
	local lines = loader_util.split_lines(buffer)
	local i = 1

	local function _parse(snippet_type)
		local line = lines[i]
		-- "snippet" or "autosnippet"
		local prefix, description = line:match(
			"^" .. snippet_type .. [[%s+(%S+)%s*(.*)]]
		)
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
		local snip = sp({
			trig = prefix,
			dscr = description,
			wordTrig = true,
		}, body)
		table.insert(snippets[snippet_type], snip)
	end

	while i <= #lines do
		local line = lines[i]
		if vim.startswith(line, "snippet") then
			_parse("snippet")
		elseif vim.startswith(line, "autosnippet") then
			_parse("autosnippet")
		elseif vim.startswith(line, "extends") then
			extends = vim.split(vim.trim(line:sub(8)), "[,%s]+")
			i = i + 1
		elseif vim.startswith(line, "#") or line:find("^%s*$") then
			-- comment and blank line
			i = i + 1
		else
			error(("invalid line in %s: %s"):format(filename, i))
		end
	end

	return snippets.snippet, snippets.autosnippet, extends
end

local function load_snippet_file(path)
	if not Path.exists(path) then
		return
	end

	local snippet, autosnippet, extends

	if cache.path_snippets[path] then
		snippet = cache.path_snippets[path].snippet
		autosnippet = cache.path_snippets[path].snippet
		extends = cache.path_snippets[path].extends
	else
		local buffer = Path.read_file(path)
		snippet, autosnippet, extends = parse_snipmate(buffer)
		cache.path_snippets[path] = {
			snippet = snippet,
			autosnippet = autosnippet,
			extends = extends,
		}
	end

	return snippet, autosnippet, extends
end

local M = {}

function M._load(ft, collection_files)
	local snippets = {}
	local autosnippets = {}
	-- _load might be called for non-existing filetype via `extends`-directive,
	-- protect against that via `or {}` (we fail silently, though, maybe we
	-- should throw an error/print some message).
	for _, path in ipairs(collection_files[ft] or {}) do
		local file_snippets, file_autosnippets, extends = load_snippet_file(
			path
		)
		vim.list_extend(snippets, file_snippets)
		vim.list_extend(autosnippets, file_autosnippets)
		for _, extend in ipairs(extends) do
			local extend_snippets, extend_autosnippets = M._load(
				extend,
				collection_files
			)
			vim.list_extend(snippets, extend_snippets)
			vim.list_extend(autosnippets, extend_autosnippets)
		end
	end
	return snippets, autosnippets
end

function M.load(opts)
	-- we need all paths available in the collection for `extends`.
	-- load_paths alone is influenced by in/exclude.
	local load_paths, collection_paths =
		loader_util.get_load_paths_snipmate_like(
			opts,
			"snippets",
			"snippets"
		)

	-- also add files from collection to cache (collection of all loaded
	-- files by filetype, useful for editing files for some filetype).
	loader_util.extend_ft_paths(cache.ft_paths, load_paths)

	for ft, _ in pairs(load_paths) do
		local snippets, autosnippets = M._load(ft, collection_paths)
		ls.add_snippets(ft, snippets, { type = "snippets" })
		ls.add_snippets(ft, autosnippets, { type = "autosnippets" })
	end
end

function M._lazyload()
	local fts = util.get_snippet_filetypes()
	for _, ft in ipairs(fts) do
		if not cache.lazy_loaded_ft[ft] then
			-- iterate over collections.
			for _, collection_load_paths in ipairs(cache.lazy_load_paths) do
				-- don't load if this ft wasn't included/was excluded.
				if collection_load_paths[ft] then
					local snippets, autosnippets = M._load(
						ft,
						collection_load_paths.collection
					)
					ls.add_snippets(ft, snippets, { type = "snippets" })
					ls.add_snippets(ft, autosnippets, { type = "autosnippets" })
				end
			end
			cache.lazy_loaded_ft[ft] = true
		end
	end
end

function M.lazy_load(opts)
	local load_paths, collection_paths =
		loader_util.get_load_paths_snipmate_like(
			opts,
			"snippets",
			"snippets"
		)

	loader_util.extend_ft_paths(cache.ft_paths, load_paths)

	for ft, _ in pairs(load_paths) do
		if cache.lazy_loaded_ft[ft] then
			-- instantly load snippets if they were already loaded...
			local snippets, autosnippets = M._load(ft, collection_paths)
			ls.add_snippets(ft, snippets, { type = "snippets" })
			ls.add_snippets(ft, autosnippets, { type = "autosnippets" })
			-- clear from load_paths to prevent duplicat loads.
			load_paths[ft] = nil
		end
	end
	load_paths.collection = collection_paths
	table.insert(cache.lazy_load_paths, load_paths)
end

vim.cmd([[
augroup _luasnip_snipmate_lazy_load
	au!
	au BufWinEnter,FileType * lua require("luasnip.loaders.from_snipmate")._lazyload()
augroup END
]])

return M
