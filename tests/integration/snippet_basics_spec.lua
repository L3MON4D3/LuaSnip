local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("snippets_basic", function()
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

	it("Can expand Snippets via snip_expand", function()
		local snip = [[
			s("trig", {
				t"the snippet expands"
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "the snippet expands" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		-- screen already is in correct state, set `unchanged`.
		screen:expect({
			grid = [[
			the snippet expands^                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
	end)

	it("Can accept custom jump_into_func.", function()
		local snip = [[
		]]
		exec_lua([[
			ls.add_snippets("all", {
				s("trig", {
					i(1, "test"),
					i(2, "test")
				})
			})
		]])

		feed("itrig")
		exec_lua([[
			ls.expand({
				jump_into_func = function(snip)
					izero = snip.insert_nodes[0]
					require("luasnip.util.util").no_region_check_wrap(izero.jump_into, izero, 1)
				end
			})
		]])
		screen:expect({
			grid = [[
			testtest^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Can expand Snippets from `all` via <Plug>", function()
		exec_lua([[
			ls.add_snippets("all", {
					s("snip", {
						t"the snippet expands"
					})
				}
			)
		]])
		feed("isnip<Plug>luasnip-expand-or-jump")
		screen:expect({
			grid = [[
			the snippet expands^                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Can jump around in simple snippets.", function()
		local snip = [[
			s("trig", {
				t"text", i(1), t"text again", i(2), t"and again"
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "texttext againand again" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			text^text againand again                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua([[
			ls.jump(1)
		]])
		screen:expect({
			grid = [[
		  texttext again^and again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]],
		})
		exec_lua([[
			ls.jump(-1)
		]])
		screen:expect({
			grid = [[
		  text^text againand again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]],
		})
		exec_lua([[
			ls.jump(1)
			ls.jump(1)
		]])
		screen:expect({
			grid = [[
		  texttext againand again^                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]],
		})
	end)

	it("Can jump around in simple snippets via <Plug>.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"text", i(1), t"text again", i(2), t"and again"
				}) )
		]])
		screen:expect({
			grid = [[
			text^text againand again                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<Plug>luasnip-jump-next")
		screen:expect({
			grid = [[
		  texttext again^and again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]],
		})
		feed("<Plug>luasnip-jump-prev")
		screen:expect({
			grid = [[
		  text^text againand again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]],
		})
		feed("<Plug>luasnip-jump-next<Plug>luasnip-jump-next")
		screen:expect({
			grid = [[
		  texttext againand again^                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]],
		})
	end)

	it("Can expand and jump out of nested snippets.", function()
		local snip = [[
			s("trig", {
				t"a[", i(1), t"]a", i(2), t"b"
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "a[]ab" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a[a[^]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})

		-- jump into second of inner.
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a[a[]a^b]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})

		-- jump to i(0) of inner.
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a[a[]ab^]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})

		-- jump to second of outer.
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a[a[]ab]a^b                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})

		-- jump back into first of outer.
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			a[^a{3:[]ab}]ab                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			unchanged = true,
		})

		-- jump back before outer.
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			^a[a[]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
		-- the snippet is not active anymore (cursor position doesn't change from last expansion).
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			^a[a[]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
	end)

	it("history=true allows jumping back into exited snippet.", function()
		-- mainly the same as the previous test, only diverges after jumping
		-- back into the inner snippet since history is enabled here.
		local expand_snip = [[
			ls.config.setup({
				history=true
			})

			ls.snip_expand(s("trig", {
				t"a[", i(1), t"]a", i(2), t"b"
			}) )
		]]
		exec_lua(expand_snip)
		-- jump behind snippet.
		exec_lua("ls.jump(1)")
		exec_lua("ls.jump(1)")
		exec_lua(expand_snip)

		screen:expect({
			grid = [[
			a[]aba[^]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})

		-- jump to
		-- 1. -1 of second
		-- 2. 0 of first
		-- 2. 2 of first
		exec_lua("ls.jump(-1)")
		exec_lua("ls.jump(-1)")
		exec_lua("ls.jump(-1)")

		screen:expect({
			grid = [[
			a[]a^ba[]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})

		-- jump through second:
		exec_lua("ls.jump(1)")
		exec_lua("ls.jump(1)")
		exec_lua("ls.jump(1)")
		exec_lua("ls.jump(1)")
		exec_lua("ls.jump(1)")

		screen:expect({
			grid = [[
			a[]aba[]ab^                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it(
		"Can jump back from nested into outer snippet with history=true.",
		function()
			-- mainly the same as the previous test, only diverges after jumping
			-- back into the inner snippet since history is enabled here.
			local expand_snip = [[
			ls.config.setup({
				history=true
			})

			ls.snip_expand(s("trig", {
				t"a[", i(1), t"]a", i(2), t"b"
			}) )
		]]
			exec_lua(expand_snip)
			exec_lua(expand_snip)
			screen:expect({
				grid = [[
			a[a[^]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			-- jump into second of inner.
			exec_lua("ls.jump(1)")
			screen:expect({
				grid = [[
			a[a[]a^b]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			-- jump to i(0) of inner.
			exec_lua("ls.jump(1)")
			screen:expect({
				grid = [[
			a[a[]ab^]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			-- jump to second of outer.
			exec_lua("ls.jump(1)")
			screen:expect({
				grid = [[
			a[a[]ab]a^b                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			-- jump back into first of outer (it's now just text since history is false.).
			exec_lua("ls.jump(-1)")
			screen:expect({
				grid = [[
			a[^a{3:[]ab}]ab                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
				unchanged = true,
			})

			-- jump back into inner snippet (since history is true).
			exec_lua("ls.jump(-1)")
			screen:expect({
				grid = [[
			a[a[]ab^]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			exec_lua("ls.jump(-1)")
			screen:expect({
				grid = [[
			a[a[]a^b]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			exec_lua("ls.jump(-1)")
			screen:expect({
				grid = [[
			a[a[^]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			exec_lua("ls.jump(-1)")
			screen:expect({
				grid = [[
			a[^a[]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			exec_lua("ls.jump(-1)")
			screen:expect({
				grid = [[
			^a[a[]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
				unchanged = true,
			})

			-- and we can jump back into the outer snippet, one last time.
			exec_lua("ls.jump(1)")
			screen:expect({
				grid = [[
			a[^a{3:[]ab}]ab                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
				unchanged = true,
			})
		end
	)

	it("Snippets are indented.", function()
		local snip = [[
			s("trig", {
				t{"the snippet expands", "and is indeted properly."}
			})
		]]
		feed("i<Tab>")
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			        the snippet expands                       |
			        and is indeted properly.^                  |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Tabs are expanded correctly", function()
		local snip = [[
			parse("trig", "\ta", {dedent = false})
		]]
		feed("i<Space><Space>")
		exec("set expandtab | set shiftwidth=8")
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			        a^                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("ISN also expands tabs correctly.", function()
		local snip = [[
			s("trig", {
				isn(1, {
					t{"", "\ta"}
				}, "$PARENT_INDENT  ")
			})
		]]
		exec("set expandtab | set shiftwidth=8")

		feed("7i<Space><Esc>i")
		exec_lua("ls.snip_expand(" .. snip .. ")")

		-- a is indented to the 16th column, not just the 8th.
		screen:expect({
			grid = [[
			                                                  |
			                a^                                 |
			{2:-- INSERT --}                                      |]],
		})
		--  .......|.......|
	end)

	it("env is extended", function()
		local snip = [[
			s("trig", {
				l(l.EXTENDED)
			}, {
				callbacks = {
					[-1] = {
						[events.pre_expand] = function()
							return {
								env_override = {
									EXTENDED = "woah :o"
								}
							}
						end
					}
				}
			})
		]]
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			woah :o^                                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
