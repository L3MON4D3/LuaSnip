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

	it("{region,delete}_check_events works correctly", function()
		exec_lua([[
			ls.setup({
				history = true,
				region_check_events = {"CursorHold", "InsertLeave"},
				delete_check_events = "TextChanged,InsertEnter",
			})

			ls.snip_expand(s("a", {
				t"sometext", i(1, "someinsertnode")
			}))
		]])
		screen:expect({
			grid = [[
  sometext^s{3:omeinsertnode}                            |
  {0:~                                                 }|
  {2:-- SELECT --}                                      |
]],
		})
		-- leave snippet-area, and trigger insertLeave.
		feed("<Esc>o<Esc>")
		screen:expect({
			grid = [[
  sometextsomeinsertnode                            |
  ^                                                  |
                                                    |
]],
		})
		-- make sure we're in the last tabstop (ie. region_check_events did its
		-- job).
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
  sometextsomeinsertnode                            |
  ^                                                  |
                                                    |
]],
		})
		-- not really necessary, but feels safer this way.
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
  sometext^s{3:omeinsertnode}                            |
                                                    |
  {2:-- SELECT --}                                      |
]],
		})

		-- delete snippet text
		feed("<Esc>dd")
		-- make sure the snippet is no longer active.
		assert.is_true(exec_lua([[
			return ls.session.current_nodes[vim.api.nvim_get_current_buf()] == nil
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
					"dscr",
					[[{"thedescription"}]],
				},
				{ [[ s({trig="a"}, { t"justsometext" }) ]], "dscr", [[{"a"}]] },

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
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 40)
		screen:attach()
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
end)
