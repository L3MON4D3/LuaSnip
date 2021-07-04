local ls = require("luasnip")
local uv = vim.loop

local function json_decode(data)
	local status, result = pcall(vim.fn.json_decode, data)
	if status then
		return result
	else
		return nil, result
	end
end

local sep = (function()
	if jit then
		local os = string.lower(jit.os)
		if os == "linux" or os == "osx" or os == "bsd" then
			return "/"
		else
			return "\\"
		end
	else
		return package.config:sub(1, 1)
	end
end)()

local function path_join(a, b)
	return table.concat({ a, b }, sep)
end
local function path_exists(path)
	return uv.fs_stat(path) and true or false
end

local function async_read_file(path, jump_if_error, callback)
	uv.fs_open(path, "r", 438, function(err, fd)
		if not jump_if_error then
			assert(not err, err)
		else
			if err then
				return
			end
		end
		uv.fs_fstat(fd, function(err, stat)
			assert(not err, err)
			uv.fs_read(fd, stat.size, 0, function(err, data)
				assert(not err, err)
				uv.fs_close(fd, function(err)
					assert(not err, err)
					return callback(data)
				end)
			end)
		end)
	end)
end

local function load_snippet_file(langs, snippet_set_path)
	if not path_exists(snippet_set_path) then
		return
	end
	async_read_file(
		snippet_set_path,
		true,
		vim.schedule_wrap(function(data)
			local snippet_set_data = json_decode(data)
			for _, lang in pairs(langs) do
				local lang_snips = ls.snippets[lang] or {}

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
							table.insert(
								lang_snips,
								ls.parser.parse_snippet({
									trig = prefix,
									name = name,
									dscr = parts.description or name,
									wordTrig = true,
								}, body)
							)
						end
					end)
				end
				ls.snippets[lang] = lang_snips
			end
		end)
	)
end

local function load_snippet_folder(root, opts)
	local package = path_join(root, "package.json")
	async_read_file(
		package,
		true,
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

				if #langs then
					load_snippet_file(
						langs,
						path_join(root, snippet_entry.path)
					)
				end
			end
		end)
	)
end

function filter_list(list, exclude, include)
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

function list_to_set(list)
	if not list then
		return list
	end
	local out = {}
	for _, item in ipairs(list) do
		out[item] = true
	end
	return out
end

local function get_snippets_rtp()
	return vim.tbl_map(function(itm)
		return vim.fn.fnamemodify(itm, ":h")
	end, vim.api.nvim_get_runtime_file(
		"package.json",
		true
	))
end

-- remove /init.lua or /init.vim  most of the time ~/.config/nvim/
local MYCONFIG_ROOT = vim.env.MYVIMRC:gsub("/[^/]+$", "")
function expand_path(path)
	local expanded = path:gsub("^~", vim.env.HOME):gsub("^[.]", MYCONFIG_ROOT)
	return uv.fs_realpath(expanded)
end

local M = {}
function M.load(opts)
	opts = opts or {}
	-- nil (unset) to include all languages (default), a list for the ones you wanna include
	opts.include = list_to_set(opts.include)

	-- A list for the ones you wanna exclude (empty by default)
	opts.exclude = list_to_set(opts.exclude) or {}

	-- list of paths to crawl for loading (could be a table or a comma-separated-list)
	if type(opts.paths) ~= "table" and opts.paths ~= nil then
		opts.paths = vim.split(opts.paths, ",")
	else
		opts.paths = get_snippets_rtp()
	end

	for _, path in ipairs(opts.paths) do
		local full_path = expand_path(path)
		if full_path then
			load_snippet_folder(full_path, opts)
		end
	end
end

return M
