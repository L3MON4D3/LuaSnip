local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("selection", function()
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
			[3] = { background = Screen.colors.LightGrey },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Text inside an insertNode is SELECTed", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"text", i(1, "some text"), t"text"
				}) )
		]])

		-- looks a bit weird, but is correct.
		screen:expect({
			grid = [[
			text^s{3:ome text}text                                 |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			unchanged = true,
		})
	end)

	it(
		"Text inside an insertNode is SELECTed with selection=exclusive",
		function()
			helpers.exec("set selection=exclusive")
			exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"text", i(1, "some text"), t"text"
				}) )
		]])

			-- looks a bit weird, but is correct.
			screen:expect({
				grid = [[
			text{3:^some text}text                                 |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
				unchanged = true,
			})
		end
	)

	it("Selection includes linebreak", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					i(1, {"first line", ""})
				}) )
		]])
		feed("replaced")

		-- note the empty second line.
		screen:expect({
			grid = [[
			replaced^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
	end)

	it("Selection includes linebreak with selection=exclusive", function()
		helpers.exec("set selection=exclusive")
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					i(1, {"first line", ""})
				}) )
		]])
		feed("replaced")

		-- note the empty second line.
		screen:expect({
			grid = [[
			replaced^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
	end)

	it("Multiline Selection works fine", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					i(1, {"first line", "second line"})
				}) )
		]])
		feed("replaced")

		-- note the empty second line.
		screen:expect({
			grid = [[
			replaced^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
	end)

	it("Multiline Selection works fine with selection=exclusive", function()
		helpers.exec("set selection=exclusive")
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					i(1, {"first line", "second line"})
				}) )
		]])
		feed("replaced")

		-- note the empty second line.
		screen:expect({
			grid = [[
			replaced^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
	end)
end)
