local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("RestoreNode", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = {bold=true, foreground=Screen.colors.Blue},
			[1] = {bold=true, foreground=Screen.colors.Brown},
			[2] = {bold=true},
			[3] = {background = Screen.colors.LightGray};
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Node is stored+restored with choiceNode.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					c(1, {
						r(nil, "restore_key", i(1, "aaaa")),
						-- converted to snippetNode.
						{
							t"\"", r(1, "restore_key"), t"\""
						},
						{
							t"'", r(1, "restore_key"), t"'"
						}
					})
				}) )
		]])
		screen:expect{grid=[[
			^a{3:aaa}                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		feed("bbbb")
		exec_lua("ls.change_choice(1)")
		screen:expect{grid=[[
			"^b{3:bbb}"                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		feed("cccc")
		exec_lua("ls.change_choice(1)")
		screen:expect{grid=[[
			'^c{3:ccc}'                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)

	it("Node is stored+restored with dynamicNode.", function()
		exec_lua([[
			local function fnc(args, snip)
				return sn(nil, {
					t(args[1]), t" ", r(1, "restore_key", i(1, "aaaa"))
				})
			end

			ls.snip_expand(s("trig", {
				i(1, "a"), t" -> ", d(2, fnc, {1})
			}))
		]])
		screen:expect{grid=[[
			^a -> a aaaa                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		-- change text in restoreNode
		exec_lua("ls.jump(1)")
		feed("bbbb")
		screen:expect{grid=[[
			a -> a bbbb^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}

		-- jump into 1 of outer snippet, change it and jump so an update is triggered.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.jump(1)")
		screen:expect{grid=[[
			c -> c ^b{3:bbb}                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)
end)
