local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua

describe("luasnip.util.str:dedent", function()
	local function check(test_name, input, output)
		it(test_name, function()
			assert.are.same(
				output,
				exec_lua(
					'return require("luasnip.util.str").dedent([['
						.. input
						.. "]])"
				)
			)
		end)
	end

	check("2 and 0", "   one", "one")
	check("0 and 2", "one\n  two", "one\n  two")
	check("2 and 1", "  one\n two", " one\ntwo")
	check("2 and 2", "  one\n  two", "one\ntwo")
end)
