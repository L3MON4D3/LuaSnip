local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("FunctionNode", function()
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

	it("Text generated on expand/general test of functionality.", function()
		exec_lua([[
			local function test(args, snip)
				return "it expands"
			end

			ls.snip_expand(
				s("trig", {
					f(test, {})
				}) )
		]])

		screen:expect({
			grid = [[
			it expands^                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Updates when argnodes' text changes + args as table.", function()
		exec_lua([[
			local function func(args, snip)
				return args[1]
			end

			ls.snip_expand(
				s("trig", {
					i(1, "a"), t" -> ", f(func, 1), t" == ", f(func, {1})
				}) )
		]])
		screen:expect({
			grid = [[
			^a -> a == a                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- does updating manually work?
		feed("b")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			b^ -> b == b                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- does updating by jumping work?
		feed("<BS>c")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			c -> c == c^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
