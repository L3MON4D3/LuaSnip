local ls_helpers = require("helpers")
local exec_lua, feed = ls_helpers.exec_lua, ls_helpers.feed
local Screen = require("test.functional.ui.screen")

describe("selection", function()
	local screen

	before_each(function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = ls_helpers.new_screen(50, 3)
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
			ls_helpers.exec("set selection=exclusive")
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
		ls_helpers.exec("set selection=exclusive")
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
		ls_helpers.exec("set selection=exclusive")
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

	it("Selection works when starting at a linebreak.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"asdf", i(1, {"", "second line"})
				}) )
		]])
		-- ^ denotes cursor, has to be behind "f".
		screen:expect({
			grid = [[
			asdf^                                              |
			{3:second line}                                       |
			{2:-- SELECT --}                                      |]],
		})
	end)
end)
