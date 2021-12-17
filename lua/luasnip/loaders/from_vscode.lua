local ls = require("luasnip")
local caches = require("luasnip.loaders._caches")
local util = require("luasnip.util.util")
local loader_util = require("luasnip.loaders.util")
local Path = require("luasnip.util.path")
local session = require("luasnip.session")

local function json_decode(data)
	local status, result = pcall(util.json_decode, data)
	if status then
		return result
	else
		return nil, result
	end
end

local function load_snippet_file(langs, snippet_set_path)
	if not Path.exists(snippet_set_path) then
		return
	end
	Path.async_read_file(
		snippet_set_path,
		vim.schedule_wrap(function(data)
			local snippet_set_data = json_decode(data)
			if snippet_set_data == nil then
				return
			end

			for _, lang in pairs(langs) do
				local lang_snips = ls.snippets[lang] or {}
				local auto_lang_snips = ls.autosnippets[lang] or {}
				for name, parts in pairs(snippet_set_data) do
					local body = type(parts.body) == "string" and parts.body
						or table.concat(parts.body, "\n")

					-- There are still some snippets that fail while loading
					pcall(function()
						-- Sometimes it's a list of prefixes instead of a single one
						local prefixes = type(parts.prefix) == "table"
								and parts.prefix
							or { parts.prefix }
						for _, prefix in ipairs(prefixes) do
							local ls_conf = parts.luasnip or {}

							local snip = ls.parser.parse_snippet({
								trig = prefix,
								name = name,
								dscr = parts.description or name,
								wordTrig = true,
							}, body)

							if ls_conf.autotrigger then
								table.insert(auto_lang_snips, snip)
							else
								table.insert(lang_snips, snip)
							end
						end
					end)
				end
				ls.snippets[lang] = lang_snips
				ls.autosnippets[lang] = auto_lang_snips
				ls.refresh_notify(lang)
			end
		end)
	)
end

local function filter_list(list, exclude, include)
	local out = {}
	for _, entry in ipairs(list) do
		if exclude[entry] then
			goto continue
		end
		-- If include is nil then it's true
		if include == nil or include[entry] then
			table.insert(out, entry)
		end
		::continue::
	end
	return out
end

local function load_snippet_folder(root, opts)
	local package = Path.join(root, "package.json")
	Path.async_read_file(
		package,
		vim.schedule_wrap(function(data)
			local package_data = json_decode(data)
			if
				not (
					package_data
					and package_data.contributes
					and package_data.contributes.snippets
				)
			then
				return
			end

			for _, snippet_entry in pairs(package_data.contributes.snippets) do
				local langs = snippet_entry.language

				if type(snippet_entry.language) ~= "table" then
					langs = { langs }
				end
				langs = filter_list(langs, opts.exclude, opts.include)

				if #langs ~= 0 then
					load_snippet_file(
						langs,
						Path.join(root, snippet_entry.path)
					)
				end
			end
		end)
	)
end

local function get_snippet_rtp()
	return vim.tbl_map(function(itm)
		return vim.fn.fnamemodify(itm, ":h")
	end, vim.api.nvim_get_runtime_file("package.json", true))
end

local M = {}
function M.load(opts)
	opts = opts or {}
	-- nil (unset) to include all languages (default), a list for the ones you wanna include
	opts.include = loader_util.filetypelist_to_set(opts.include)

	-- A list for the ones you wanna exclude (empty by default)
	opts.exclude = loader_util.filetypelist_to_set(opts.exclude) or {}

	-- list of paths to crawl for loading (could be a table or a comma-separated-list)
	if not opts.paths then
		opts.paths = get_snippet_rtp()
	elseif type(opts.paths) == "string" then
		opts.paths = vim.split(opts.paths, ",")
	end

	opts.paths = vim.tbl_map(Path.expand, opts.paths) -- Expand before deduping, fake paths will become nil
	opts.paths = util.deduplicate(opts.paths) -- Remove doppelgänger paths and ditch nil ones

	for _, path in ipairs(opts.paths) do
		load_snippet_folder(path, opts)
	end
end

function M._luasnip_vscode_lazy_load()
	local fts = util.get_snippet_filetypes()
	for _, ft in ipairs(fts) do
		if not caches.lazy_loaded_ft[ft] then
			caches.lazy_loaded_ft[ft] = true
			M.load({ paths = caches.lazy_load_paths, include = { ft } })
		end
	end
end

function M.lazy_load(opts)
	opts = opts or {}

	-- We have to do this here too, because we have to store them in lozy_load_paths
	if not opts.paths then
		opts.paths = get_snippet_rtp()
	elseif type(opts.paths) == "string" then
		opts.paths = vim.split(opts.paths, ",")
	end
	vim.list_extend(caches.lazy_load_paths, opts.paths)

	caches.lazy_load_paths = util.deduplicate(caches.lazy_load_paths) -- Remove doppelgänger paths and ditch nil ones

	vim.cmd([[
    augroup _luasnip_vscode_lazy_load
        autocmd!
        au BufWinEnter,FileType * lua require('luasnip.loaders.from_vscode')._luasnip_vscode_lazy_load()
        au User LuasnipCleanup lua require('luasnip.loaders._caches').clean()
    augroup END
	]])
end

return M
