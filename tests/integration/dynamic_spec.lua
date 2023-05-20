local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("DynamicNode", function()
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

	it("The snippet is generated.", function()
		local snip = [[
			s("trig", {
				d(1, function(args, snip)
					return sn(nil, {t"yep"})
				end, {})
			})
		]]
		ls_helpers.static_docstring_test(snip, { "yep" }, { "${1:yep}$0" })
		exec_lua("ls.snip_expand(" .. snip .. ")")

		screen:expect({
			grid = [[
			yep^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("The snippet is jumped into and indented.", function()
		local snip = [[
			s("trig", {
				d(1, function(args, snip)
					return sn(nil, { t"yep ", i(1, { "line1", "line2" }) })
				end, {})
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "yep line1", "line2" },
			{ "${1:yep ${1:line1", "line2}}$0" }
		)
		feed("i<Tab>")
		exec_lua("ls.snip_expand(" .. snip .. ")")

		-- selected and indented.
		screen:expect({
			grid = [[
			        yep ^l{3:ine1}                                 |
			{3:        line2}                                     |
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("The dynamicNode is updated if argnode changes.", function()
		local snip = [[
			s("trig", {
				i(1, "preset"),
				d(2, function(args, snip)
					return sn(nil, { i(1, args[1]) })
				end, 1)
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "presetpreset" },
			{ "${1:preset}${2:${1:preset}}$0" }
		)

		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^p{3:reset}preset                                      |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- shouldn't be updated yet.
		feed("nomorepreset")
		screen:expect({
			grid = [[
			nomorepreset^preset                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			nomorepreset^nomorepreset                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- check if it updates after jumping.
		feed("reset")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			nomorepresetreset^n{3:omorepresetreset}                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Multiple argnodes update the dynamicNode correctly as well.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				i(2, "b"),
				d(3, function(args, snip)
					return sn(nil, { i(1, args[1][1]..args[2][1]) })
				end, {1, 2})
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "abab" },
			{ "${1:a}${2:b}${3:${1:ab}}$0" }
		)

		exec_lua("ls.snip_expand(" .. snip .. ")")
		-- one char of selection is just the cursor, so no ${3:...}.
		screen:expect({
			grid = [[
			^abab                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("c")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			c^bcb                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("d")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			cd^cd                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	-- test this case here because dynamicNode is responsible for setting up everything
	-- for the restoreNode.
	it("restoreNode works in dynamicNode.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				d(2, function(args, snip)
					return sn(nil, { t(args[1]), r(1, "restore_key", i(1, "sample_text")) })
				end, 1)
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "aasample_text" },
			{ "${1:a}${2:a${1:${1:sample_text}}}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^aasample_text                                     |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- change text of insertNode inside restoreNode.
		exec_lua("ls.jump(1)")
		feed("bbb")
		screen:expect({
			grid = [[
			aabbb^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- update the dynamicNode (by changing text of the first insertNode), the
		-- textNode should change while the insertNode-changes are preserved.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			c^cbbb                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	-- from #491
	it("dynamicNode propagates indent.", function()
		local snip = [[
			s("fails", d(1, function ()
				return sn(nil, fmt("{}", {f(function () return {"a", "b"} end)}))
			end))
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "a", "b" },
			{ "${1:a", "b}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a                                                 |
			b^                                                 |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("dynamicNode works in dynamicNode.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				d(2, function(args, snip)
					return sn(nil, { i(1, args[1]), d(2, function(args, snip) return sn(nil, { t(args[1]) }) end, 1) })
				end, {1})
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "aaa" },
			{ "${1:a}${2:${1:a}${2:a}}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^aaa                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- update inner dynamicNode.
		exec_lua("ls.jump(1)")
		feed("b")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			ab^b                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- update outer dynamicNode.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			c^cc                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	ls_helpers.check_global_node_refs("nested fNode can depend on outside iNode", {
		first = { 1, "i1" },
	}, function()
		local snip = [[
			s("arg", {
				i(1, "aaa", {key = "i1"}),
				d(2, function()
					return sn(nil, {
						f(function(args)
							return args[1]
						end, {_luasnip_test_resolve("first")})
					})
				end)
			})
		]]
		ls_helpers.static_docstring_test(
			snip,
			{ "aaaaaa" },
			{ "${1:aaa}${2:aaa}$0" }
		)
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^a{3:aa}aaa                                            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		feed("some text")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			some text^some text                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<Esc>cc")
	end)

	ls_helpers.check_global_node_refs(
		"generates correct static text when depending on node generated by dynamicNode",
		{
			first = { { 1, 0, 1 }, "in_dynode" },
		},
		function()
			local snip = [[
		s("trig", {
			-- arg will not be available when the static text is first queried.
			f(function(args) return args[1] end, _luasnip_test_resolve("first")),
			d(1, function(args)
				return sn(nil, {i(1, "argnode-text", {key = "in_dynode"})})
			end, {})
		}) ]]
			ls_helpers.static_docstring_test(
				snip,
				{ "argnode-textargnode-text" },
				{ "argnode-text${1:${1:argnode-text}}$0" }
			)
		end
	)

	it(
		"generates correct static text when using environment variables.",
		function()
			exec_lua([[
                             ls.env_namespace("DYN", {
                                 vars = {ONE = "1", TWO = {"1", "2"}},
                                 multiline_vars = {"TWO"}
                              })
                        ]])
			local snip = [[

			s("trig", {
				d(1, function(args, parent)
					return sn(nil, {
                                            t(parent.snippet.env.DYN_ONE),
                                            t"..", 
                                            t(parent.snippet.env.DYN_TWO),
                                            t"..",
                                            t(tostring(#parent.snippet.env.DYN_TWO)), -- This one behaves as a table
                                            t"..",
                                            t(parent.snippet.env.WTF_YEA),  -- Unknow vars also work
                                        })
				end, {})
			})
                        ]]
			ls_helpers.static_docstring_test(
				snip,
				{ "$DYN_ONE..$DYN_TWO..1..$WTF_YEA" },
				{ "${1:$DYN_ONE..$DYN_TWO..1..$WTF_YEA}$0" }
			)
		end
	)
end)
