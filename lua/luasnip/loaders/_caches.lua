local Cache = {}

function Cache:clean()
	self.lazy_load_paths = {}
	self.lazy_loaded_ft = {}
end

local function new_cache()
	-- returns the table the metatable was set on.
	return setmetatable({
		lazy_load_paths = {},
		lazy_loaded_ft = {},
		ft_paths = {}, -- key is file type, value are paths of .snippets files.
		path_snippets = {}, -- key is file path, value are parsed snippets in it.
	}, {
		__index = Cache,
	})
end

return {
	vscode = new_cache(),
	snipmate = new_cache(),
	lua = new_cache(),
}
