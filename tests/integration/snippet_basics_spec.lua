local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec
local Screen = require("test.functional.ui.screen")

describe("snippets_basic", function()
	local screen

	before_each(function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip({ setup_parsers = true })

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
		exec_lua("vim.wait(10, function() end)")
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

		-- jump back through outer.
		-- (can no longer enter it through connections to other snippet)
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			^a[a[]ab]ab                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged = true,
		})
		-- last snippet is not forgotten (yet).
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a[^a{3:[]ab}]ab                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("<Esc>o")
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a[a[]ab]ab                                        |
			a[^]ab                                             |
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(-1) ls.jump(-1)")

		-- first snippet can't be accessed anymore.
		screen:expect({
			grid = [[
			a[a[]ab]ab                                        |
			^a[]ab                                             |
			{2:-- INSERT --}                                      |]],
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
			exec_lua("vim.wait(10, function() end)")
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

	it("snip_env respects behaviour (set)", function()
		exec_lua([[
			ls.setup({
				snip_env = {
					__snip_env_behaviour = "set",
					_s = true
				}
			})
			-- remove this variable from global environment.
			s = nil
		]])
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets2_env_test_set"
			)
		)
	end)
	it("snip_env respects behaviour (extend)", function()
		exec_lua([[
			ls.setup({
				snip_env = {
					__snip_env_behaviour = "extend",
					_s = true,
					-- default has i as function, check override.
					i = true
				}
			})
			-- remove this variable from global environment.
			s = nil
		]])
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets2_env_test_extend"
			)
		)
	end)

	it("autocommands are triggered by events", function()
		assert.is_true(exec_lua([[
			vim.api.nvim_create_autocmd("User", {
				pattern = "LuasnipInsertNodeEnter",
				callback = function()
					inode_did_enter = true
				end
			})
			ls.snip_expand(
				s("trig", {
					t"text", i(1), t"text again", i(2), t"and again"
				}) )
			return inode_did_enter
		]]))
	end)

	it("autocommands are registered in different formats", function()
		local function test_combination(setting_name, overridefn_name)
			exec_lua(([[
					local config_events = {
						{"InsertLeave","CursorHold"},
						"InsertLeave,CursorHold",
						"InsertLeave, CursorHold",
						"InsertLeave",
						{"InsertLeave"}
					}
					local check_events = {
						{"InsertLeave","CursorHold"},
						{"InsertLeave","CursorHold"},
						{"InsertLeave","CursorHold"},
						{"InsertLeave"},
						{"InsertLeave"}
					}

					for i, config_event in ipairs(config_events) do
						a_set = false
						ls.%s = function() a_set = true end

						ls.setup({
							%s = config_event
						})
						for _, event in ipairs(check_events[i]) do
							a_set = false
							vim.api.nvim_exec_autocmds(event, {})
							assert(a_set)
						end
					end
				]]):format(overridefn_name, setting_name))
		end

		test_combination("region_check_events", "exit_out_of_region")
		test_combination("delete_check_events", "unlink_current_if_deleted")
		test_combination("update_events", "active_update_dependents")
		test_combination("updateevents", "active_update_dependents")
	end)

	it(
		"jump_destination works for snippets where `node.active` is important",
		function()
			exec_lua([[
			ls.snip_expand(s("", {i(1), sn(2, {t"this is skipped"}), i(3)}))
		]])
			assert.are.same(
				exec_lua(
					[[return ls.jump_destination(1).absolute_insert_position]]
				),
				{ 3 }
			)
		end
	)

	it(
		"wordTrig, regTrig, hidden, name, description, docstring work and default correctly",
		function()
			local snip_wt_val = {
				{
					[[ s({trig="a", wordTrig = false}, { t"justsometext" }) ]],
					"wordTrig",
					"false",
				},
				{
					[[ s({trig="a", wordTrig = true}, { t"justsometext" }) ]],
					"wordTrig",
					"true",
				},
				{
					[[ s({trig="a"}, { t"justsometext" }) ]],
					"wordTrig",
					"true",
				},

				{
					[[ s({trig="a", regTrig = false}, { t"justsometext" }) ]],
					"regTrig",
					"false",
				},
				{
					[[ s({trig="a", regTrig = true}, { t"justsometext" }) ]],
					"regTrig",
					"true",
				},
				{
					[[ s({trig="a"}, { t"justsometext" }) ]],
					"regTrig",
					"false",
				},

				{
					[[ s({trig="a", hidden = false}, { t"justsometext" }) ]],
					"hidden",
					"false",
				},
				{
					[[ s({trig="a", hidden = true}, { t"justsometext" }) ]],
					"hidden",
					"true",
				},
				{ [[ s({trig="a"}, { t"justsometext" }) ]], "hidden", "false" },

				{
					[[ s({trig="a", name = "thename"}, { t"justsometext" }) ]],
					"name",
					[["thename"]],
				},
				{ [[ s({trig="a"}, { t"justsometext" }) ]], "name", [["a"]] },

				{
					[[ s({trig="a", dscr = "thedescription"}, { t"justsometext" }) ]],
					"description",
					[[{"thedescription"}]],
				},
				{
					[[ s({trig="a"}, { t"justsometext" }) ]],
					"description",
					[[{"a"}]],
				},
				{
					[[ s({trig="a", dscr = "thedescription"}, { t"justsometext" }) ]],
					"dscr",
					[[{"thedescription"}]],
				},

				{
					[[ s({trig="a", docstring = "thedocstring"}, { t"justsometext" }) ]],
					"docstring",
					[[{"thedocstring"}]],
				},
				{
					[[ s({trig="a"}, { t"justsometext" }) ]],
					"docstring",
					"nil",
				},
			}

			for _, pair in ipairs(snip_wt_val) do
				assert.is_true(exec_lua(([[
				local snip = %s
				return vim.deep_equal(snip.%s, %s)
			]]):format(pair[1], pair[2], pair[3])))
			end
		end
	)

	it("LuaSnipListAvailable works", function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = ls_helpers.new_screen(50, 40)
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue1 },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGrey },
			[4] = { bold = true, reverse = true },
			[5] = { bold = true, foreground = Screen.colors.SeaGreen4 },
			[6] = { foreground = Screen.colors.Red1 },
		})
		exec_lua([[
			ls.add_snippets("all", {
				s({trig="a"}, { t"justsometexta" }),
				s({trig="b"}, { t"justsometextb" }),
				s({trig="c"}, { t"justsometextc" }),
			})
		]])
		feed(":LuaSnipListAvailable<Cr>")
		screen:expect({
			grid = [[
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{4:                                                  }|
			{                                                 |
			  [""] = {},                                      |
			  all = { {                                       |
			      description = { "a" },                      |
			      name = "a",                                 |
			      regTrig = false,                            |
			      trigger = "a",                              |
			      wordTrig = true                             |
			    }, {                                          |
			      description = { "b" },                      |
			      name = "b",                                 |
			      regTrig = false,                            |
			      trigger = "b",                              |
			      wordTrig = true                             |
			    }, {                                          |
			      description = { "c" },                      |
			      name = "c",                                 |
			      regTrig = false,                            |
			      trigger = "c",                              |
			      wordTrig = true                             |
			    } }                                           |
			}                                                 |
			{5:Press ENTER or type command to continue}^           |]],
		})
		feed("<Cr>")
	end)

	it("get_keyed_node works", function()
		exec_lua([[
			ls.snip_expand(s("", {
				i(1, "a", {key = "a"}),
				c(2, {
					{t"asdf", i(1, "b", {key = "b"})},
					d(nil, function()
						return sn(nil, {i(1, "c", {key = "c"})})
					end, {})
				})
			}))
		]])
		exec_lua("snip = ls.session.current_nodes[1].parent.snippet")
		assert.are.same(
			{ "a" },
			exec_lua([[return snip:get_keyed_node("a"):get_text()]])
		)
		assert.are.same(
			{ "b" },
			exec_lua([[return snip:get_keyed_node("b"):get_text()]])
		)
		assert.are.same(
			exec_lua([[return vim.NIL]]),
			exec_lua([[return snip:get_keyed_node("c")]])
		)

		exec_lua("ls.jump(1) ls.change_choice(1)")

		assert.are.same(
			{ "c" },
			exec_lua([[return snip:get_keyed_node("c"):get_text()]])
		)
	end)

	it("text is inserted into the selected node.", function()
		exec_lua([[
			ls.snip_expand(s("", {
				i(1), i(2), sn(3, {
					i(2), i(1)
				}), i(4)
			}))
		]])

		feed("aa")
		screen:expect({
			grid = [[
			aa^                                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(1)")

		-- will insert here later.
		exec_lua("ls.jump(1)")

		feed("cc")
		screen:expect({
			grid = [[
			aacc^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(1)")

		feed("dd")
		screen:expect({
			grid = [[
			aadd^cc                                            |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(1)")

		feed("ee")
		screen:expect({
			grid = [[
			aaddccee^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			aa^d{3:d}ccee                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			aadd^c{3:c}ee                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(-1)")
		feed("bb")
		screen:expect({
			grid = [[
			aabb^ddccee                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			^a{3:a}bbddccee                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			aa^b{3:b}ddccee                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it(
		"text is inserted into the selected node, when dynamicNode is present",
		function()
			exec_lua([[
				ls.snip_expand(s("", {
					i(4), i(1), d(2, function()
						return sn(nil, {i(2), i(1)})
					end, {3}), i(3, "text??")
				}))
			]])
			screen:expect({
				grid = [[
				^text??                                            |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})

			exec_lua("ls.jump(1) ls.jump(1) ls.jump(1)")
			feed("refresh dNode ")
			screen:expect({
				grid = [[
				refresh dNode ^                                    |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
			exec_lua("ls.jump(1)")
			screen:expect({
				grid = [[
				^refresh dNode                                     |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
			feed("shifts dNode? ")
			screen:expect([[
				shifts dNode? ^refresh dNode                       |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]])
			-- doing all jump in the same exec_lua fails :/
			-- Maybe some weird timing-issue with feed..
			exec_lua("ls.jump(-1)")
			exec_lua("ls.jump(-1)")
			exec_lua("ls.jump(-1)")
			exec_lua("ls.jump(-1)")
			feed("also shifts dNode ")
			screen:expect([[
				shifts dNode? also shifts dNode ^refresh dNode     |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]])

			exec_lua("ls.jump(1)")
			feed("dNode1 ")

			screen:expect([[
				shifts dNode? also shifts dNode dNode1 ^refresh dNo|
				de                                                |
				{2:-- INSERT --}                                      |]])
			exec_lua("ls.jump(1)")
			feed("dNode2 ")
			screen:expect([[
				shifts dNode? also shifts dNode dNode2 ^dNode1 refr|
				esh dNode                                         |
				{2:-- INSERT --}                                      |]])

			exec_lua("ls.jump(-1)")
			exec_lua("ls.jump(-1)")
			screen:expect([[
				shifts dNode? ^a{3:lso shifts dNode }dNode2 dNode1 refr|
				esh dNode                                         |
				{2:-- SELECT --}                                      |]])

			exec_lua("ls.jump(1)")
			screen:expect([[
				shifts dNode? also shifts dNode dNode2 ^d{3:Node1 }refr|
				esh dNode                                         |
				{2:-- SELECT --}                                      |]])
			exec_lua("ls.jump(1)")
			screen:expect([[
				shifts dNode? also shifts dNode ^d{3:Node2 }dNode1 refr|
				esh dNode                                         |
				{2:-- SELECT --}                                      |]])
			exec_lua("ls.jump(1)")
			screen:expect([[
				shifts dNode? also shifts dNode dNode2 dNode1 ^r{3:efr}|
				{3:esh dNode }                                        |
				{2:-- SELECT --}                                      |]])
			exec_lua("ls.jump(1)")
			screen:expect([[
				^s{3:hifts dNode? }also shifts dNode dNode2 dNode1 refr|
				esh dNode                                         |
				{2:-- SELECT --}                                      |]])
			exec_lua("ls.jump(1)")
			screen:expect([[
				shifts dNode? also shifts dNode dNode2 dNode1 refr|
				esh dNode ^                                        |
				{2:-- INSERT --}                                      |]])
		end
	)
	it(
		"text is inserted into the selected node, when choiceNode is present",
		function()
			exec_lua([[
			ls.snip_expand(s("", {
				i(1),
				c(2, {
					t"asdf",
					i(nil)
				}),
				i(3, "text??")
			}))
		]])
			screen:expect({
				grid = [[
			^asdftext??                                        |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})

			-- jump to i3
			exec_lua("ls.jump(1) ls.jump(1)")
			feed("1111")
			screen:expect({
				grid = [[
			asdf1111^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})

			-- change choice, jump back
			exec_lua("ls.jump(-1) ls.change_choice(1) ls.jump(1)")
			feed("2222")
			screen:expect({
				grid = [[
			2222^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})

			-- back to i1
			exec_lua("ls.jump(-1) ls.jump(-1)")
			feed("3333")
			screen:expect({
				grid = [[
			3333^2222                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})

			exec_lua("ls.jump(1)")
			feed("4444")
			screen:expect({
				grid = [[
			33334444^2222                                      |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
		end
	)

	local engine_data = {
		-- list of: trigger, snippet-body, docTrig/inserted text, expected expansion, expected docstring
		vim = [[\(\d\+\)]],
		pattern = [[(%d+)]],
		ecma = [[(\d+)]],
	}
	for engine, trig in pairs(engine_data) do
		it('trigEngine "' .. engine .. '" works', function()
			exec_lua(
				[[
				trigEngine, trig = ...
				snip = s({trig = trig, docTrig = "3", trigEngine = trigEngine}, {t"c1: ", l(l.CAPTURE1)})
				ls.add_snippets("all", {snip})
			]],
				engine,
				trig
			)
			feed("i<Space>3")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
				 c1: 3^                                            |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
			-- make sure docTrig works with all engines.
			assert.is_true(
				exec_lua([[return snip:get_docstring()[1] == "c1: 3$0"]])
			)
		end)
	end

	for engine, trig in pairs(engine_data) do
		it('trigEngine "' .. engine .. '" respects `max_len`', function()
			exec_lua(
				[[
				trigEngine, trig = ...
				snip = s({trig=trig, wordTrig=false, trigEngine=trigEngine, trigEngineOpts={max_len = 2}}, {t"c1: ", l(l.CAPTURE1)})
				ls.add_snippets("all", {snip})
			]],
				engine,
				trig
			)
			feed("i<Space>33")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
				 c1: 33^                                           |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})

			feed("<Cr>333")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
				 c1: 33                                           |
				3c1: 33^                                           |
				{2:-- INSERT --}                                      |]],
			})
		end)
	end

	it("custom trigEngine works", function()
		exec_lua([[
			ls.add_snippets("all", {
				s({trig = "", trigEngine = function(trigger)
					return function(line_to_cursor, trigger)
						if line_to_cursor:match("asdf") then
							return "asdf", {}
						end
					end
				end}, {t"aaaaa"})
			})
		]])
		feed("iasdf")
		exec_lua([[ ls.expand() ]])
		screen:expect({
			grid = [[
			aaaaa^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Selection is yanked correctly.", function()
		feed("iasdfasdfasdf<Cr>")
		feed("𝔼sdfasdfasdf<Cr>")
		feed("asdfasdfasdf<Cr>")
		feed("<Esc>ggvjjll<Tab><Esc>u")
		assert.are.same(
			exec_lua(
				[[return vim.api.nvim_buf_get_var(0, "LUASNIP_SELECT_RAW")]]
			),
			{ "asdfasdfasdf", "𝔼sdfasdfasdf", "asd" }
		)

		feed("ggll<C-V>lllljj<Tab><Esc>u")
		assert.are.same(
			exec_lua(
				[[return vim.api.nvim_buf_get_var(0, "LUASNIP_SELECT_RAW")]]
			),
			{ "dfasd", "dfasd", "dfasd" }
		)
	end)

	it("Selection is yanked correctly with mutlibyte characters.", function()
		feed("i𝔼f-𝔼abc<Esc>v^<Tab><Esc>u")
		assert.are.same(
			exec_lua(
				[[return vim.api.nvim_buf_get_var(0, "LUASNIP_SELECT_RAW")]]
			),
			{ "𝔼f-𝔼abc" }
		)

		feed("^lvlll<Tab><Esc>u")
		assert.are.same(
			exec_lua(
				[[return vim.api.nvim_buf_get_var(0, "LUASNIP_SELECT_RAW")]]
			),
			{ "f-𝔼a" }
		)

		feed("^V<Tab><Esc>u")
		assert.are.same(
			exec_lua(
				[[return vim.api.nvim_buf_get_var(0, "LUASNIP_SELECT_RAW")]]
			),
			{ "𝔼f-𝔼abc" }
		)
	end)

	it("Nested $0 remains active if there is no real next node.", function()
		exec_lua([[
			ls.add_snippets("all", {
				s("aa", { i(1, "a:"), t"(", i(0), t")" })
			})
		]])

		-- expand nested.
		feed("iaa")
		exec_lua([[ ls.expand() ]])
		exec_lua([[ ls.jump(1) ]])
		screen:expect({
			grid = [[
			a:(^)                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("aa")
		exec_lua([[ ls.expand() ]])
		exec_lua([[ ls.jump(1) ]])
		screen:expect({
			grid = [[
			a:(a:(^))                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("aa")
		exec_lua([[ ls.expand() ]])
		exec_lua([[ ls.jump(1) ]])
		screen:expect({
			grid = [[
			a:(a:(a:(^)))                                      |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- jump should not move cursor!
		-- for some reason need multiple jumps to trigger the mistake.
		exec_lua([[ ls.jump(1)]])
		exec_lua([[ ls.jump(1)]])
		screen:expect({ unchanged = true })
	end)

	it("exit_out_of_region activates last node of snippet-root.", function()
		exec_lua([[
			ls.setup({
				link_children = true
			})

			ls.add_snippets("all", { s("aa", { i(1), t"( ", i(0, "0-text"), t" )" }) })
		]])

		feed("iaa")
		exec_lua("ls.expand()")
		feed("<Esc>lllliaa")
		exec_lua("ls.expand()")
		exec_lua("ls.jump(-1) ls.jump(-1)")
		screen:expect({
			grid = [[
			^( 0-( 0-text )text )                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>o")
		exec_lua("ls.exit_out_of_region(ls.session.current_nodes[1])")

		-- verify that we are in the $0 of the nested snippet.
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			( 0-^( 0-text )text )                              |
			                                                  |
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			( 0-( ^0{3:-text} )text )                              |
			                                                  |
			{2:-- SELECT --}                                      |]],
		})
	end)

	it(
		"exit_roots exits when the last node of snippet-root is reached.",
		function()
			exec_lua([[
			ls.setup({
				exit_roots = true
			})
			ls.add_snippets("all", {
			s("aa", { t{"( "}, i(1, "1"), t{" )"}, i(0, "0") })
			})
		]])

			feed("iaa")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
			( ^1 )0                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})
			feed("aa")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
			( ( ^1 )0 )0                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})
			-- verify we do not exit when reaching to a child root
			exec_lua("ls.jump(1) ls.jump(-1)")
			screen:expect({ unchanged = true })

			-- be sure that reaching root $0 exits.
			exec_lua("ls.jump(1) ls.jump(1) ls.jump(-1)")
			screen:expect({
				grid = [[
			( ( 1 )0 )^0                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})
		end
	)
	it("exit_roots = false stays in the root node but exits child.", function()
		exec_lua([[
			ls.setup({
				exit_roots = false
			})
			ls.add_snippets("all", {
			s("aa", { t{"( "}, i(1, "1"), t{" )"}, i(0, "0") })
			})
		]])

		feed("iaa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			( ^1 )0                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		-- screen:snapshot_util()
		feed("aa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			( ( ^1 )0 )0                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		-- do not exit when reaching to a child root
		exec_lua("ls.jump(1) ls.jump(-1)")
		screen:expect({ unchanged = true })
		-- root $0 does not exit.
		exec_lua("ls.jump(1) ls.jump(1) ls.jump(-1)")
		screen:expect({
			grid = [[
			( ^({3: 1 )0} )0                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		-- new root snippet exits earlier root.
		exec_lua("ls.jump(1)")
		feed("aa")
		exec_lua("ls.expand()")
		exec_lua("ls.jump(-1) ls.jump(-1)")
		screen:expect({
			grid = [[
			( ( 1 )0 )^( 1 )0                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("focus correctly adjusts gravities of parent-snippets.", function()
		exec_lua([[
			ls.setup{
				link_children = true
			}
		]])
		exec_lua([[ls.lsp_expand("a$1$1a")]])
		exec_lua([[ls.lsp_expand("b$1")]])
		feed("ccc")
		exec_lua([[ls.active_update_dependents()]])
		feed("dddd")
		-- Here's how this fails if `focus` does not behave correctly (ie. only
		-- adjusts extmarks in the snippet the current node is inside):
		-- child has a changed $1, triggers update of own snippets, and
		-- transitively of the parent-$1.
		-- Since the parent has a functionNode that copies the $1's text, it
		-- has to first focus the fNode, and update the text. This shifts the
		-- gravity of the end of the parent-$1-extmark to the left.
		-- Here the first failure may occur: if the child-extmark is not
		-- adjusted as well, it will contain the text that belongs to the
		-- functionNode.
		-- The second issue that may occur is a bit more subtle:
		-- After the whole update procedure is done, we have to refocus the
		-- current node (since we have to assume that the update changed focus
		-- s.t. the current node no longer has correct extmarks).
		-- If, in doing this, the parent-$1-extmark end-gravity is not restored
		-- to the right, the child-snippet will extend beyond the extmark of
		-- its parent-node, the parent-$1.
		exec_lua([[ls.jump(-1) ls.jump(-1)]])
		-- highlights outer $1.
		exec_lua([[ls.jump(1)]])
		screen:expect({
			grid = [[
			a^b{3:cccdddd}bcccdddda                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		-- and then inner $1.
		exec_lua([[ls.jump(1)]])
		screen:expect({
			grid = [[
			ab^c{3:ccdddd}bcccdddda                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("focus correcty adjusts gravity of parent-snippets, v2.", function()
		exec_lua([[
			ls.setup({
				history = true
			})
		]])

		exec_lua([[ls.lsp_expand("\\$$1\\$")]])
		feed("<Esc>l")
		exec_lua([[ls.lsp_expand("\\rightarrow")]])
		screen:expect({
			grid = [[
			$\rightarrow^$                                     |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<Space>s")
		exec_lua([[ls.jump(1)]])
		screen:expect({
			grid = [[
			$\rightarrow s$^                                   |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- make sure the entire placeholder is highlighted.
		exec_lua([[ls.jump(-1)]])
		screen:expect({
			grid = [[
			$^\{3:rightarrow s}$                                   |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua([[ls.jump(-1)]])
		screen:expect({
			grid = [[
			$\rightarrow^ s$                                   |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("unlink_current works.", function()
		exec_lua([[ls.lsp_expand("$1 adsf $2")]])
		exec_lua([[ls.jump( 1)]])
		screen:expect({
			grid = [[
			 adsf ^                                            |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua([[ls.jump(-1)]])
		screen:expect({
			grid = [[
			^ adsf                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua([[ls.unlink_current()]])
		exec_lua([[ls.jump( 1)]])
		screen:expect({ unchanged = true })
	end)

	it("node-event is not triggered twice for exitNode.", function()
		exec_lua([[
			counter = 0
			snip = s("mk", t"asdf", {callbacks = {[-1] = {[events.leave] = function()
				counter = counter + 1
			end}}})
		]])
		exec_lua([[ls.snip_expand(snip)]])
		assert.are.same(1, exec_lua("return counter"))

		-- +1 for entering the exit-node of the second expansion.
		exec_lua([[ls.snip_expand(snip)]])
		assert.are.same(2, exec_lua("return counter"))
	end)

	it("node-callbacks are executed correctly.", function()
		exec_lua([[
			enter_qwer = false
			enter_qwer_via_parent = false

			snip = s("foo", {
				t"asdf", i(1, "qwer", {node_callbacks = {[events.enter] = function()
					enter_qwer = true
				end}})
			}, {callbacks = {[1] = { [events.enter] = function()
				enter_qwer_via_parent = true
			end}} } )

			ls.snip_expand(snip)
		]])

		assert.are.same(true, exec_lua("return enter_qwer"))
		assert.are.same(true, exec_lua("return enter_qwer_via_parent"))

		exec_lua([[
			enter_snode = false
			enter_snode_m1 = false
			enter_snode_via_parent = false

			snip = s("foo", {
				sn(1, {t"qwer"}, {
					node_callbacks = {[events.enter] = function()
						enter_snode = true
					end},
					callbacks = { [-1] = {
						[events.enter] = function()
							enter_snode_m1 = true
						end }}
				} )
			}, {callbacks = {[1] = { [events.enter] = function()
				enter_snode_via_parent = true
			end}}, } )

			ls.snip_expand(snip)
		]])

		assert.are.same(true, exec_lua("return enter_snode"))
		assert.are.same(true, exec_lua("return enter_snode_m1"))
		assert.are.same(true, exec_lua("return enter_snode_via_parent"))
	end)

	it("Correct filetype is recognized via treesitter.", function()
		exec_lua([=[
			ls.setup({
				ft_func = require("luasnip.extras.filetype_functions").from_cursor_pos
			})
			ls.add_snippets("lua", {
				s("asdf", t[[print("qwer")]])
			})
		]=])
		exec("set ft=lua")
		feed([[ilocal function a()  end<Esc>hhhi]])
		screen:expect({
			grid = [[
			local function a() ^ end                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed([[asdf]])
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			local function a() print("qwer")^ end              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("expand-position may be moved in pre_expand.", function()
		feed("i.")

		exec_lua([[
			snip = s("foo", {
				t"asdf"
			}, {callbacks = {[-1] = { [events.pre_expand] = function(node, event_args)
				vim.api.nvim_buf_set_extmark(0, ls.session.ns_id, 0,0, {id = event_args.expand_pos_mark_id})
			end}} } )

			ls.snip_expand(snip)
		]])

		screen:expect({
			grid = [[
				asdf^.                                             |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
		})
	end)

	it("autosnippets are triggered in macro.", function()
		exec_lua([[
			ls.add_snippets("all", {
				s({trig="qwer", snippetType="autosnippet"}, { t"asdf" }) })
		]])
		feed("qaiqwer<Esc>qo<Esc>@a")
		screen:expect({
			grid = [[
			qwer                                              |
			qwe^r                                              |
			                                                  |]],
		})
	end)

	it(
		"cursor position is correctly updated after expanding an autosnippet.",
		function()
			exec_lua([[
			vim.o.concealcursor = 'i'

			ls.setup{
				history = true,
				enable_autosnippets = true,
			}
			ls.add_snippets("all", {
					ls.s({trig="asdf", snippetType="autosnippet"}, {ls.t"System.out.println(", ls.i(1, ""), ls.t")"})
			})
		]])
			feed("iasdf")
			-- this test seems to mostly fail on nvim0.7, but let's include it here anyway.
			screen:expect({
				grid = [[
    System.out.println(^)                              |
    {0:~                                                 }|
    {2:-- INSERT --}                                      |
  ]],
			})
		end
	)
end)
