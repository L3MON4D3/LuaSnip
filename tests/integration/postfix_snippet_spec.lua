local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("postfix snippets", function()
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

	it(
		"creates a postfix snippet which changes the previous text once expanded",
		function()
			exec_lua([[
				ls.add_snippets("all", {
					pf(".parens", {
						f(function(_, parent)
							return "(" .. parent.env.POSTFIX_MATCH .. ")"
						end, {})
					})
				})
			]])

			feed("ibar.parens")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
				(bar)^                                             |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end
	)

	it("default pattern works with a _, -, and .", function()
		exec_lua([[
			ls.add_snippets("all", {
				pf(".parens", {
					f(function(_, parent)
						return "(" .. parent.env.POSTFIX_MATCH .. ")"
					end, {})
				})
			})
		]])

		feed("ithis_is-a.weird_variable.parens")
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			(this_is-a.weird_variable)^                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can take alternate matching strings", function()
		exec_lua([[
			ls.add_snippets("all", {
				pf({trig = ".parens", match_pattern = "^.+$"}, {
					f(function(_, parent)
						return "(" .. parent.env.POSTFIX_MATCH .. ")"
					end, {})
				})
			})
		]])

		feed([[ithis should take the whole line.parens]])
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			(this should take the whole line)^                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("wordTrig can't accidentally be set", function()
		exec_lua([[
			ls.add_snippets("all", {
				pf({trig = ".parens", match_pattern = "^.+$", wordTrig = true}, {
					f(function(_, parent)
						return "(" .. parent.env.POSTFIX_MATCH .. ")"
					end, {})
				})
			})
		]])

		feed([[ithis should take the whole line.parens]])
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			(this should take the whole line)^                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("allows the user to set a callback on the same event", function()
		exec_lua([[
			ls.add_snippets("all", {
				pf(
					".parens",
					{
					  f(function(_, parent)
						return "("
						  .. parent.env.POSTFIX_MATCH
						  .. " "
						  .. parent.env.another_field 
						  .. ")"
					  end),
					},
					{
						callbacks = {
							[-1] = {
								[events.pre_expand] = function(snippet, event_args)
									return {
										env_override = {
											another_field = "data from another env field",
										},
									}
								end,
							},
						},
					}
				)
			})
		]])

		feed([[ifoo.parens]])
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			(foo data from another env field)^                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	-- test resolveExpandParams in general.
	it("respects user-provided resolveExpandParams.", function()
		exec_lua([[
			ls.add_snippets("all", {
				pf({
					trig = ".parens",
					match_pattern = "^.+$",
					resolveExpandParams = function(snip, line_to_cursor, matched_trigger, captures)
						return {
							env_override = { asdf = "asdf" }
						}
					end
				}, {
					f(function(_, parent)
						return "(" .. parent.env.POSTFIX_MATCH .. ")" .. parent.env.asdf
					end, {})
				})
			})
		]])

		feed([[ithis should expand.parens]])
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			(this should expand)asdf^                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("respects user-provided condition.", function()
		exec_lua([[
			ls.add_snippets("all", {
				pf({
					trig = ".parens",
					match_pattern = "^.+$",
					condition = function()
						return false
					end
				}, {
					f(function(_, parent)
						return "(" .. parent.env.POSTFIX_MATCH .. ")" .. parent.env.asdf
					end, {})
				})
			})
		]])

		feed([[ithis should not expand.parens]])
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			this should not expand.parens^                     |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
