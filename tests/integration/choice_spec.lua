local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("ChoiceNode", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 3)
		screen:attach()
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

	it("Can change choice.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					c(1, {
						t"a",
						t"b"
					})
				}) )
		]])
		screen:expect({
			grid = [[
			^a                                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^b                                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Changed content of choice is restored.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					c(1, {
						-- parsed as snippetNode.
						{
							i(1, "a"), t" ", c(2, {
							                 	t"a",
							                 	t"b"
							                 })
						},
						t"b"
					})
				}) )
		]])
		screen:expect({
			grid = [[
			^a a                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change text in insertNode.
		feed("c")
		exec_lua("ls.jump(1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			c ^b                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- change choice on outer choiceNode.
		exec_lua("ls.jump(-1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^b                                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^c b                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)
end)
