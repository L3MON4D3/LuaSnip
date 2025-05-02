local ls_helpers = require("helpers")
local exec_lua, feed = ls_helpers.exec_lua, ls_helpers.feed
local Screen = require("test.functional.ui.screen")

describe("ChoiceNode", function()
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

	it("Can change choice.", function()
		local snip = [[
			s("trig", {
				c(1, {
					t"a",
					t"b"
				})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "a" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

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
		local snip = [[
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
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "a a" }
		)
		assert.are.same(
			exec_lua("return " .. snip .. ":get_docstring()"),
			{ "${1:${${1:a} ${2:a}}}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		-- next jump leads to t"a".
		assert.are.same(
			exec_lua([[return ls.jump_destination(1).absolute_insert_position]]),
			{ 1, 1, 2, 1 }
		)
		assert.are.same(exec_lua("return ls.get_current_choices()"), {
			"${${1:a} ${2:a}}",
			"b",
		})

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

		-- back-jump leads to 1-node.
		assert.are.same(
			exec_lua(
				[[return ls.jump_destination(-1).absolute_insert_position]]
			),
			{ 1, 1, 1 }
		)

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
		assert.are.same(
			exec_lua([[return ls.jump_destination(1).absolute_insert_position]]),
			{ 1, 1, 2, 2 }
		)
		screen:expect({
			grid = [[
			^c b                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Choices are indented properly.", function()
		local snip = [[
			s("trig", {
				c(1, {
					t{"a", "a"},
					t{"b", "b"}
				})
			})
		]]

		feed("i<Tab>")
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			        ^a                                         |
			        a                                         |
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			        ^b                                         |
			        b                                         |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("dynamicNode works in choiceNode.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				c(2, {
					d(nil, function(args, snip)
						return sn(nil, { i(1, args[1]) })
					end, 1),
					t"none"
				})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aa" }
		)
		assert.are.same(
			exec_lua("return " .. snip .. ":get_docstring()"),
			{ "${1:a}${2:${${1:a}}}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		-- next jump leads inside dynamicNode.
		assert.are.same(
			exec_lua([[return ls.jump_destination(1).absolute_insert_position]]),
			{ 2, 1, 0, 1 }
		)

		screen:expect({
			grid = [[
			^aa                                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		feed("b")
		exec_lua("ls.active_update_dependents()")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			b^b                                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		assert.are.same(exec_lua("return ls.get_current_choices()"), {
			"${${1:a}}",
			"none",
		})

		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			b^none                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- won't update, the dynamicNode isn't visible.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			c^none                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- now changeChoice should show the updated dynamicNode.
		exec_lua("ls.jump(1)")
		exec_lua("ls.change_choice()")
		screen:expect({
			grid = [[
			c^c                                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("get_current_choices works with non-default f/dNode", function()
		exec_lua([[
			ls.snip_expand(s("test", {
				c(1, {
					t"a",
					sn(nil, {f(function()
						return "c"
					end) }),
					t"b",
					f(function()
						return "d"
					end),
					d(nil, function()
						return sn(nil, t"e")
					end)
				})
			}))
		]])

		assert.are.same(exec_lua("return ls.get_current_choices()"), {
			"a",
			"${c}",
			"b",
			"d",
			"${e}",
		})
	end)

	it("can depend on choiceNode.", function()
		exec_lua([[
			ls.snip_expand(
				s("sss",{
					c(1, {
					  t("."),
					  t("by bullet points"),
					  t("by creating stories"),
					}, { key = "sum-typ" }),
					f(function(args)
					  local res ={}
					  if string.match(args[1][1],"bullet") then
						table.insert(res, "by-bullet-points")
					  elseif string.match(args[1][1],"stories") then
						table.insert(res, "by-creating-stories")
					  else
						table.insert(res," -->")
					  end
					  return res
					end, k("sum-typ")),
				})
			)
		]])

		screen:expect({
			grid = [[
			^. -->                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^by bullet pointsby-bullet-points                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
