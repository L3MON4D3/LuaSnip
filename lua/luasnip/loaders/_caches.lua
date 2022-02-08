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
	}, {
		__index = Cache,
	})
end

return {
	vscode = new_cache(),
	snipmate = new_cache(),
}
