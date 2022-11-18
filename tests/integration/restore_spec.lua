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
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Node is stored+restored with choiceNode.", function()
		local snip = [[
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
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aaaa" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			^a{3:aaa}                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- can use get_docstring on inactive restoreNode.
		assert.are.same(exec_lua("return ls.get_current_choices()"), {
			[[${${1:aaaa}}]],
			[[${"${${1:aaaa}}"}]],
			[[${'${${1:aaaa}}'}]],
		})

		feed("bbbb")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			"^b{3:bbb}"                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("cccc")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			'^c{3:ccc}'                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- make sure the change persisted.
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^c{3:ccc}                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Node is stored+restored with dynamicNode.", function()
		local snip = [[
			s("trig", {
				i(1, "a"), t" -> ", d(2, function(args, snip)
					return sn(nil, {
						t(args[1]), t" ", r(1, "restore_key", i(1, "aaaa"))
					})
				end, {1})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "a -> a aaaa" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			^a -> a aaaa                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change text in restoreNode
		exec_lua("ls.jump(1)")
		feed("bbbb")
		screen:expect({
			grid = [[
			a -> a bbbb^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- jump into 1 of outer snippet, change it and jump so an update is triggered.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			c -> c ^b{3:bbb}                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Can restore choice.", function()
		local snip = [[s("trig", {
			c(1, {
				{
					-- insertNode to be able to switch outer choice.
					t"a", i(1), r(2, "restore_key", c(1, {
						t"c",
						t"d"
					})), t"a"
				}, {
					t"b", r(1, "restore_key"), t"b"
				}
			})
		}) ]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aca" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			a^ca                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- change inner choice.
		exec_lua("ls.jump(1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			a^da                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- change outer choice, inner choice ("b") should be restored.
		exec_lua("ls.jump(-1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			b^db                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Nested restoreNode works.", function()
		local snip = [[
			s("trig", {
				c(1, {
					r(nil, "restore_key", {
						t"aaa: ", r(1, "restore_key_2", i(1, "bbb"))
					}),
					r(1, "restore_key_2")
				})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aaa: bbb" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			aaa: ^b{3:bb}                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change text for restore_key_2, but inside restore_key.
		feed("ccc")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^c{3:cc}                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- make sure the text changed in restore_key as well.
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			aaa: ^c{3:cc}                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("functionNode in restoreNode works.", function()
		local snip = [[
			s("trig", {
				c(1, {
					r(nil, "restore_key", {
						i(1, "aaa"), f(function(args) return args[1] end, 1)
					}),
					{
						t"a",
						r(1, "restore_key"),
						t"a"
					}
				})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aaaaaa" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			^a{3:aa}aaa                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- insertNode isn't updated yet...
		feed("bbb")
		screen:expect({
			grid = [[
			bbb^aaa                                            |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- but should be updated after the choice is changed.
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			a^b{3:bb}bbba                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("restoreNode is properly indented.", function()
		local snip = [[
			s("trig", {
				r(1, "restore_key", t{"line 1", "line 2"}),
			})
		]]
		feed("i<Tab>")
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			        line 1                                    |
			        line 2^                                    |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("dynamicNode works in restoreNode.", function()
		local snip = [[
			s("trig", {
				c(1, {
					r(nil, "restore_key", {
						i(1, "aaa"), d(2, function(args) return sn(nil, { i(1, args[1]) }) end, 1)
					}),
					{
						t"a",
						r(1, "restore_key"),
						t"a"
					}
				})
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "aaaaaa" },
			{ "${1:${1:${1:aaa}${2:${1:aaa}}}}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^a{3:aa}aaa                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("bbb")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			bbb^bbb                                            |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- replace text and change choice, the dNode should be updated.
		feed("<BS><BS><BS>ccc")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			a^c{3:cc}ccca                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)
end)
