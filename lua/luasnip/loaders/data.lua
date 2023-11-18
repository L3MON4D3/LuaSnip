--- This module stores all files loaded by any of the loaders, ordered by their
--- filetype, and other data.
--- This is to facilitate luasnip.loaders.edit_snippets, and to handle
--- persistency of data, which is not given if it is stored in the module-file,
--- since the module-name we use (luasnip.loaders.*) is not necessarily the one
--- used by the user (luasnip/loader/*, for example), and the returned modules
--- are different tables.

local autotable = require("luasnip.util.auto_table").autotable

local M = {
	lua_collections = {},
	lua_ft_paths = autotable(2),

	snipmate_collections = {},
	snipmate_ft_paths = autotable(2),
	-- set by loader.
	snipmate_cache = nil,

	vscode_package_collections = {},
	vscode_standalone_watchers = {},
	vscode_ft_paths = autotable(2),
	-- set by loader.
	vscode_cache = nil,
}

return M
