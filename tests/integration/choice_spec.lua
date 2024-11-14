local ls_helpers = require("helpers")
local exec_lua, feed = ls_helpers.exec_lua, ls_helpers.feed
local Screen = require("test.functional.ui.screen")

describe("ChoiceNode", function()
	local screen

	before_each(function()
		ls_helpers.clear()
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
			"${${1:b}}",
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

	it("correctly gives current content of choices.", function()
		assert.are.same({"${1:asdf}", "qwer"}, exec_lua[[
			ls.snip_expand(s("trig", {
				c(1, {
					i(1, "asdf"),
					t"qwer"
				})
			}))
			ls.change_choice()
			return ls.get_current_choices()
		]])
	end)

	it("correctly restores the generated node of a dynamicNode.", function()
		assert.are.same({ "${1:${${1:aaa}${2:${1:aaa}}}}$0" }, exec_lua[[
			snip = s("trig", {
				c(1, {
					r(nil, "restore_key", {
						i(1, "aaa"), d(2, function(args) return sn(nil, {i(1, args[1])}) end, {1}, {snippetstring_args = true})
					}),
					{
						t"a",
						r(1, "restore_key"),
						t"a"
					}
				})
			})
			return snip:get_docstring()
		]])
		exec_lua("ls.snip_expand(snip)")
		feed("qwer")
		exec_lua("ls.jump(1)")
screen:expect({
  grid = [[
    qwer^q{3:wer}                                          |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
	exec_lua("ls.change_choice(1)")
screen:expect({
  grid = [[
    a^q{3:wer}qwera                                        |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
	end)

	it("cursor is correctly restored after change", function()
		screen:detach()

		ls_helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 7)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})

		exec_lua[=[
			ls.snip_expand(s("trig", {
				c(1, {
					fmt([[
						local {} = function()
							{}
						end
					]], {r(1, "name", i(1, "fname")), sn(2, {t{"aaaa", "bbbb"},r(1, "body", i(1, "fbody"))}) }),
					fmt([[
						local function {}()
							{}
						end
					]], {r(1, "name", i(1, "fname")), r(2, "body", i(1, "fbody"))})
				}, {restore_cursor = true})
			}))
		]=]
		exec_lua("vim.wait(10, function() end)")

		exec_lua"ls.jump(1)"
		feed("asdf<Cr>asdf<Cr>qwer<Cr><Tab>aaaa<Left><Left>")
screen:expect({
  grid = [[
    local fname = function()                          |
            aaaa                                      |
    bbbbasdf                                          |
    asdf                                              |
    qwer                                              |
            aa^aa                                      |
    {2:-- INSERT --}                                      |
  ]]
})
		exec_lua"ls.change_choice(1)"
screen:expect({
  grid = [[
    local function fname()                            |
            asdf                                      |
    asdf                                              |
    qwer                                              |
            aa^aa                                      |
    end                                               |
    {2:-- INSERT --}                                      |
  ]]
})
		exec_lua"ls.jump(-1)"
		exec_lua"ls.jump(1)"
screen:expect({
  grid = [[
    local function fname()                            |
            ^a{3:sdf}                                      |
    {3:asdf}                                              |
    {3:qwer}                                              |
    {3:        aaaa}                                      |
    end                                               |
    {2:-- SELECT --}                                      |
  ]]
})
		exec_lua"ls.change_choice(1)"
screen:expect({
  grid = [[
            aaaa                                      |
    bbbb^a{3:sdf}                                          |
    {3:asdf}                                              |
    {3:qwer}                                              |
    {3:        aaaa}                                      |
    end                                               |
    {2:-- SELECT --}                                      |
  ]]
})
		feed("i<Esc><C-Y>")
		exec_lua"ls.change_choice(1)"
		exec_lua[=[
			ls.snip_expand(s("for", {
				t"for ", c(1, {
					sn(nil, {i(1, "k"), t", ", i(2, "v"), t" in ", c(3, {{t"pairs(",i(1),t")"}, {t"ipairs(",i(1),t")"}, i(nil)}, {restore_cursor = true}) }),
					sn(nil, {i(1, "val"), t" in ", i(2) }),
					sn(nil, {i(1, "i"), t" = ", i(2), t", ", i(3) }),
					fmt([[{} in vim.gsplit({})]], {i(1, "str"), i(2)})
				}, {restore_cursor = true}), t{" do", "\t"}, isn(2, {dl(1, l.LS_SELECT_DEDENT)}, "$PARENT_INDENT\t"), t{"", "end"}
			}))
		]=]
screen:expect({
  grid = [[
    local function fname()                            |
            for ^k, v in pairs() do                    |
                                                      |
            endi                                      |
    end                                               |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
		exec_lua"ls.change_choice(1)"
screen:expect({
  grid = [[
    local function fname()                            |
            for ^v{3:al} in  do                            |
                                                      |
            endi                                      |
    end                                               |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
		exec_lua"ls.jump(1)"
		exec_lua"ls.jump(1)"
screen:expect({
  grid = [[
    local function fname()                            |
            for val in  do                            |
                    ^                                  |
            endi                                      |
    end                                               |
    {0:~                                                 }|
    {2:-- INSERT --}                                      |
  ]]
})
		exec_lua"ls.change_choice(1)"
screen:expect({
  grid = [[
    local fname = function()                          |
            aaaa                                      |
    bbbbfor val in  do                                |
                    ^                                  |
            endi                                      |
    end                                               |
    {2:-- INSERT --}                                      |
  ]]
})
	end)

	it("select_choice works.", function()
		exec_lua[=[
			ls.snip_expand(s("for", {
				t"for ", c(1, {
					sn(nil, {i(1, "k"), t", ", i(2, "v"), t" in ", c(3, {{t"pairs(",i(1),t")"}, {t"ipairs(",i(1),t")"}, i(nil)}, {restore_cursor = true}) }),
					sn(nil, {i(1, "val"), t" in ", i(2) }),
					sn(nil, {i(1, "i"), t" = ", i(2), t", ", i(3) }),
					fmt([[{} in vim.gsplit({})]], {i(1, "str"), i(2)})
				}, {restore_cursor = true}), t{" do", "\t"}, isn(2, {dl(1, l.LS_SELECT_DEDENT)}, "$PARENT_INDENT\t"), t{"", "end"}
			}))
		]=]
		feed("<cmd>lua require('luasnip.extras.select_choice')()<Cr>2<Cr>")
screen:expect({
  grid = [[
    for ^v{3:al} in  do                                    |
                                                      |
    {2:-- SELECT --}                                      |
  ]]
})
		feed("aa<Left>")
		-- simulate vim.ui.select that modifies the cursor.
		-- Can happen in the wild with plugins like dressing.nvim (although
		-- those usually just leave INSERT), and we would like to prevent it.
		exec_lua[[
			vim.ui.select = function(_,_,cb)
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes(
					"<left><left>",
					true,
					false,
					true
				),
				"nix",
				true)

				cb(nil, 2)
			end
		]]
		-- re-selecting correctly highlights text again (test by editing so the test does not pass immediately, without any changes!)
		exec_lua("require('luasnip.extras.select_choice')()")
screen:expect({
  grid = [[
    for a^a in  do                                     |
                                                      |
    {2:-- INSERT --}                                      |
  ]]
})
	end)

	it("updates the active node before changing choice.", function()
		exec_lua[[
			ls.setup({
				link_children = true
			})
			ls.snip_expand(s("trig", {
				t":",
				c(1, {
					{r(1, "key", d(1, function(args)
						if not args[1] then
							return sn(nil, {i(1, "aa", {key = "i"})})
						else
							return sn(nil, {i(1, "cc"), i(2, args[1]:gsub("a", "ee"), {key = "i"})})
						end
					end, { opt(k("i")) }, {snippetstring_args = true}))},
					{t".", r(1, "key"), t"."}
				}, {restore_cursor = true}),
				t":"
			}))
		]]
		exec_lua"ls.jump(1)"
		feed("<esc><right><right>i aa <left><left>")
screen:expect({
  grid = [[
    :ccee a^a ee:                                      |
    {0:~                                                 }|
    {2:-- INSERT --}                                      |
  ]]
})
		-- if we wouldn't update before the change_choice, the last_args of the
		-- restored dynamicNode would not fit its current content, and we'd
		-- lose the text inserted until now due to the update (as opposed to
		-- a proper restore of dynamicNode.snip, which should occur in a
		-- restoreNode).
		exec_lua"ls.change_choice(1)"
screen:expect({
  grid = [[
    :.ccee ee^ee ee.:                                  |
    {0:~                                                 }|
    {2:-- INSERT --}                                      |
  ]]
})
		exec_lua"ls.set_choice(2)"
screen:expect({ unchanged = true })

		-- test some more wild stuff, just because.
		feed("  <left> ")
		exec_lua[[
			ls.snip_expand(s("trig", {
				t":",
				c(1, {
					{r(1, "key", d(1, function(args)
						if not args[1] then
							return sn(nil, {i(1, "aa", {key = "i"})})
						else
							return sn(nil, {i(1, "cc"), i(2, args[1]:gsub("a", "ee"), {key = "i"})})
						end
					end, { opt(k("i")) }, {snippetstring_args = true}))},
					{t".", r(1, "key"), t"."}
				}, {restore_cursor = true}),
				t":"
			}))
		]]

screen:expect({
  grid = [[
    :.ccee e :^c{3:c}eeee:eee ee.:                         |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
		exec_lua"ls.jump(1)"
		feed("<esc><right><right>i aa <left><left>")
		exec_lua"ls.set_choice(2)"
screen:expect({
  grid = [[
    :.ccee e :.ccee ee^ee ee.:eee ee.:                 |
    {0:~                                                 }|
    {2:-- INSERT --}                                      |
  ]]
})

		-- reselect outer choiceNode
		exec_lua"ls.jump(-1)"
		exec_lua"ls.jump(-1)"
		exec_lua"ls.jump(-1)"
		exec_lua"ls.jump(1)"
screen:expect({
  grid = [[
    :.cc^e{3:e e :.ccee eeee ee.:eee ee}.:                 |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
		exec_lua"ls.change_choice(1)"
screen:expect({
  grid = [[
    :cc^e{3:e e :.ccee eeee ee.:eee ee}:                   |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
		exec_lua"ls.jump(1)"
		exec_lua"ls.jump(1)"
screen:expect({
  grid = [[
    :ccee e :.cc^e{3:e eeee ee}.:eee ee:                   |
    {0:~                                                 }|
    {2:-- SELECT --}                                      |
  ]]
})
	end)
end)
