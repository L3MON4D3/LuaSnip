local uv = vim.uv or vim.loop
local duplicate = require("luasnip.nodes.duplicate")

--- @class LuaSnip.Loaders.SnippetCache.Mtime
--- @field sec number
--- @field nsec number
--- Stores modified time for a file.

--- @class LuaSnip.Loaders.SnippetCache.TimeCacheEntry
--- @field mtime LuaSnip.Loaders.SnippetCache.Mtime?
--- @field data LuaSnip.Loaders.SnippetFileData
--- mtime is nil if the file does not currently exist. Since `get_fn` may still
--- return data, there's no need to treat this differently.

--- @class LuaSnip.Loaders.SnippetCache
--- SnippetCache stores snippets and other data loaded by files.
--- @field private get_fn fun(file: string): LuaSnip.Loaders.SnippetFileData
--- @field private cache table<string, LuaSnip.Loaders.SnippetCache.TimeCacheEntry>
local SnippetCache = {}
SnippetCache.__index = SnippetCache

local M = {}

--- @class LuaSnip.Loaders.SnippetFileData
--- @field snippets LuaSnip.Addable[]
--- @field autosnippets LuaSnip.Addable[]
--- @field misc table any data.

--- Create new cache.
--- @param get_fn fun(file: string): LuaSnip.Loaders.SnippetFileData
--- @return LuaSnip.Loaders.SnippetCache
function M.new(get_fn)
	return setmetatable({
		get_fn = get_fn,
		cache = {},
	}, SnippetCache)
end

--- Copy addables from data to new table.
--- @param data LuaSnip.Loaders.SnippetFileData
--- @return LuaSnip.Loaders.SnippetFileData
local function copy_filedata(data)
	--- @as LuaSnip.Loaders.SnippetFileData
	return {
		snippets = vim.tbl_map(duplicate.duplicate_addable, data.snippets),
		autosnippets = vim.tbl_map(
			duplicate.duplicate_addable,
			data.autosnippets
		),
		misc = vim.deepcopy(data.misc),
	}
end

--- Retrieve loaded data for any file, either from the cache, or directly from
--- the file.
--- For storage-efficiency (and to elide the otherwise necessary deepcopy), the
--- snippets are duplicated, which should not leak.
--- @param fname string
--- @return LuaSnip.Loaders.SnippetFileData
function SnippetCache:fetch(fname)
	local cached = self.cache[fname]
	local current_stat = uv.fs_stat(fname)

	--- @as LuaSnip.Loaders.SnippetCache.Mtime
	local mtime = current_stat and current_stat.mtime

	if
		cached
		and mtime
		and mtime.sec == cached.mtime.sec
		and mtime.nsec == cached.mtime.nsec
	then
		-- happy path: data is cached, and valid => just return cached data.
		return copy_filedata(cached.data)
	end

	-- data is stale (cache entry does not exist, file was written after
	-- cache-creation, or the file was deleted).
	-- fetch data from updated file
	local res = self.get_fn(fname)

	-- store it.
	self.cache[fname] = {
		data = res,
		mtime = mtime,
	}

	-- return it.
	-- Don't copy here, no need to.
	return res
end

return M
