local Cache = {}

function Cache:clean()
	self.lazy_load_paths = {}
	self.lazy_loaded_ft = {}
	self.ft_paths = {}
	self.path_snippets = {}
end

local function new_cache()
	-- returns the table the metatable was set on.
	return setmetatable({
		-- maps ft to list of files. Each file provides snippets for the given
		-- filetype.
		-- In snipmate:
		-- {
		--	lua = {"~/snippets/lua.snippets"},
		--	c = {"~/snippets/c.snippets", "/othersnippets/c.snippets"}
		-- }
		lazy_load_paths = {},

		-- ft -> {true, nil}.
		-- Keep track of which filetypes were already lazy_loaded to prevent
		-- duplicates.
		lazy_loaded_ft = {},

		-- key is file type, value are paths of .snippets files.
		ft_paths = {},

		path_snippets = {}, -- key is file path, value are parsed snippets in it.
	}, {
		__index = Cache,
	})
end

local M = {
	vscode = new_cache(),
	snipmate = new_cache(),
	lua = new_cache(),
}

function M.cleanup()
	M.vscode:clean()
	M.snipmate:clean()
	M.lua:clean()
end

return M
