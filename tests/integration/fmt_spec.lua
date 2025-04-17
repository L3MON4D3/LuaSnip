local ls_helpers = require("helpers")
local exec_lua, feed = ls_helpers.exec_lua, ls_helpers.feed
local Screen = require("test.functional.ui.screen")

describe("Fmt", function()
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

	it("Repeat duplicate node with same key", function()
		exec_lua([=[
    ls.add_snippets("all", {
      ls.s(
        "repeat",
        require("luasnip.extras.fmt").fmt([[
        {a} repeat {a}
        ]],
        { a = ls.i(1) },
        { repeat_duplicates = true }
        )
      )
    })
    ]=])
		feed("irepeat")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
      ^ repeat                                           |
      {0:~                                                 }|
      {2:-- INSERT --}                                      |
      ]],
		})
		feed("asdf")
		exec_lua("ls.jump()")
		screen:expect({
			grid = [[
      ^asdf repeat asdf                                  |
      {0:~                                                 }|
      {2:-- INSERT --}                                      |
      ]],
		})
	end)
end)
