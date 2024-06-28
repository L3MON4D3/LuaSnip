local ls_helpers = require("helpers")
local exec_lua, _, exec = ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec

describe("luasnip.loaders.util:", function()
	ls_helpers.clear()
	exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	it("Correctly splits scopes with spaces.", function()
		local res = exec_lua(
			[[return require("luasnip.loaders.util").scopestring_to_filetypes("javascript, typescript")]]
		)
		assert.are.same({ "javascript", "typescript" }, res)
		local res = exec_lua(
			[[return require("luasnip.loaders.util").scopestring_to_filetypes(" javascript, typescript")]]
		)
		assert.are.same({ "javascript", "typescript" }, res)
		local res = exec_lua(
			[[return require("luasnip.loaders.util").scopestring_to_filetypes("javascript , typescript ")]]
		)
		assert.are.same({ "javascript", "typescript" }, res)
	end)
end)
