local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("Extra-nodes:", function()
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

	it("matchNode works with simple strings", function()
		local snip = [[
			s("trig", {
				i(1),
				m(1, "aaa%d", "bbb", "ccc")
			})
		]]
		ls_helpers.static_docstring_test(snip, { "ccc" }, { "$1ccc$0" })
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^ccc                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- change text so it matches:
		feed("aaa3")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			aaa3^bbb                                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- ensure multiline works.
		feed("<Cr>cccc")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			aaa3                                              |
			cccc^bbb                                           |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("matchNode works with functions", function()
		local snip = [[
			s("trig", {
				i(1),
				m(1,
					function(args) return #args[1][1] == 3 end,
					function(args) return tostring(#args[1][1]) end,
					function(args) return "nope" end )
			})
		]]
		ls_helpers.static_docstring_test(snip, { "nope" }, { "$1nope$0" })
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^nope                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- make i_1 match:
		feed("aaa")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			aaa^3                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<BS>")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			aa^nope                                            |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- ensure multiline works.
		feed("a<Cr>")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			aaa                                               |
			^3                                                 |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("matchNode works with lambdas", function()
		-- create bigger screen for this test.
		-- TODO: rewrite all tests for this screen-size.
		screen:detach()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 5)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})

		local snip = [[
			s("trig", {
				i(1, "best"),
				m(1,
					l._1:gsub("e", "a"):match("tast"),
					l._1:gsub("e", "u"),
					l._1:gsub("e", "o") )
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "bestbost" },
			{ "${1:best}bost$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^b{3:est}bost                                          |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("test")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			test^tust                                          |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<BS>e")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			tese^toso                                          |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- ensure multiline works.
		feed("<Cr>test")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			tese                                              |
			test^tusu                                          |
			tust                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it(
		"matchNode uses return of condition-function for `if` if unspecified",
		function()
			local snip = [[
			s("trig", {
				i(1, "aaa"),
				m(1, function(args)
				     	return (#args[1][1] == 3 and args[1] or nil)
				     end)
			})
		]]
			ls_helpers.static_docstring_test(
				snip,
				{ "aaaaaa" },
				{ "${1:aaa}aaa$0" }
			)
			exec_lua("ls.snip_expand(" .. snip .. ")")
			screen:expect({
				grid = [[
			^a{3:aa}aaa                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})

			-- replace matching text
			feed("aa")
			exec_lua("ls.active_update_dependents()")
			screen:expect({
				grid = [[
			aa^                                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
		end
	)

	it(
		"matchNode uses return of match on condition-pattern for `if` if unspecified",
		function()
			local snip = [[
			s("trig", {
				i(1, "12"),
				m(1, "%d(%d)")
			})
		]]
			ls_helpers.static_docstring_test(snip, { "122" }, { "${1:12}2$0" })
			exec_lua("ls.snip_expand(" .. snip .. ")")
			screen:expect({
				grid = [[
			^1{3:2}2                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})
			feed("aa")
			exec_lua("ls.active_update_dependents()")
			screen:expect({
				grid = [[
			aa^                                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
		end
	)

	it(
		"matchNode uses return of condition-lambda for `if` if unspecified",
		function()
			local snip = [[
			s("trig", {
				i(1, "1324"),
				m(1, l._1:gsub("[123]", "0"):match("00(%d%d)"))
			})
		]]
			ls_helpers.static_docstring_test(
				snip,
				{ "132404" },
				{ "${1:1324}04$0" }
			)
			exec_lua("ls.snip_expand(" .. snip .. ")")
			screen:expect({
				grid = [[
			^1{3:324}04                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})

			feed("4444")
			exec_lua("ls.active_update_dependents()")
			screen:expect({
				grid = [[
			4444^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
		end
	)
end)
