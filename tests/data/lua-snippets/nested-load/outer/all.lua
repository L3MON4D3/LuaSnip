-- Loading this file triggers another load while it is still executing, as
-- happens when a snippet-file requires a module from a plugin that registers
-- its own collection.
local before = s("nested_before", t("before"))

require("luasnip.loaders.from_lua").load({
	paths = os.getenv("LUASNIP_SOURCE")
		.. "/tests/data/lua-snippets/nested-load/inner",
})

local after = s("nested_after", t("after"))

return { before, after }
