local ls_helpers = require("helpers")
local exec_lua, feed = ls_helpers.exec_lua, ls_helpers.feed
local Screen = require("test.functional.ui.screen")

describe("Simple Nodes", function()
	local screen

	before_each(function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = ls_helpers.new_screen(50, 3)
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Allow empty table as input placeholder", function()
		local snip = [[
			s("trig", {
				i(1, {})
			})
		]]
		ls_helpers.static_docstring_test(snip, { "" }, { "$1$0" })
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			^                                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
