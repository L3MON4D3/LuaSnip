local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("add_snippets", function()
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

	it("overrides previously loaded snippets with the same key", function()
		exec_lua([[
			ls.add_snippets("all", {
				ls.parser.parse_snippet("trigger1", "aaaaa")
			}, {
				key = "a"
			} )
		]])
		exec_lua([[
			ls.add_snippets("all", {
				ls.parser.parse_snippet("trigger2", "eeeee")
			}, {
				key = "a"
			} )
		]])

		feed("itrigger2")
		exec_lua("ls.expand()")
		-- snippets from second call expands.
		screen:expect({
			grid = [[
			eeeee^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<space>trigger1")
		exec_lua("ls.expand()")

		-- snippet from first call was removed.
		screen:expect({
			grid = [[
			eeeee trigger1^                                    |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("correctly loads autosnippets", function()
		exec_lua("ls.config.setup({ enable_autosnippets = true })")
		exec_lua([[
			ls.add_snippets("all", {
				ls.parser.parse_snippet("trigger1", "aaaaa")
			}, {
				type = "autosnippets"
			} )
		]])

		feed("itrigger1")
		screen:expect({
			grid = [[
			aaaaa^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can handle snippet-table", function()
		exec_lua([[
			ls.add_snippets(nil, {
				all = {
					ls.parser.parse_snippet("trigger1", "aaaaa")
				},
				c = {
					ls.parser.parse_snippet("trigger2", "eeeee")
				}
			})
		]])

		feed("itrigger1")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			aaaaa^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec("set ft=c")
		feed("<space>trigger2")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			aaaaa eeeee^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("respects priority", function()
		exec_lua([[
		ls.add_snippets("all", {
			ls.parser.parse_snippet({trig = "trig"}, "bbb")
		})
		]])

		feed("itrig")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			bbb^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua([[
		ls.add_snippets("all", {
			-- overrides previous trig-snippet
			ls.parser.parse_snippet({trig = "trig", priority = 1001}, "aaa"),
		})
		]])
		-- delete and re-trigger.
		feed("<Esc>dditrig")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			aaa^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua([[
		ls.add_snippets("all", {
			-- overrides previous trig-snippet
			ls.parser.parse_snippet({trig = "trig", priority = 999}, "ccc"),
		}, {
			override_priority = 1002
		})
		]])
		-- delete and re-trigger.
		feed("<Esc>dditrig")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			ccc^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua([[
		ls.add_snippets("all", {
			-- make sure snippet-priority isn't superseded by default_priority.
			-- check by overriding previous trig-snippet.
			ls.parser.parse_snippet({trig = "trig", priority = 1003}, "ddd"),

			-- the lower should have the higher priority (default = 1002)
			ls.parser.parse_snippet({trig = "treg", priority = 1001}, "aaa"),
			ls.parser.parse_snippet({trig = "treg"}, "bbb"),
		}, {
			default_priority = 1002
		})
		]])
		-- delete and re-trigger.
		feed("<Esc>dditrig")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			ddd^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- delete and re-trigger.
		feed("<Esc>dditreg")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			bbb^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("add autosnippets by option", function()
		exec_lua("ls.config.setup({ enable_autosnippets = true })")
		exec_lua([[
			ls.add_snippets("all", {
				ls.snippet({trig="triA", snippetType="autosnippet"}, {ls.text_node("helloAworld")}, {})
			}, {
				key = "a",
			} )
		]])
		exec_lua([[
			ls.add_snippets("all", {
				ls.snippet({trig="triB", snippetType="snippet"}, {ls.text_node("helloBworld")}, {})
			}, {
				key = "b",
			} )
		]])
		exec_lua([[
			ls.add_snippets("all", {
				ls.snippet({trig="triC", snippetType=nil}, {ls.text_node("helloCworld")}, {})
			}, {
				key = "c",
				type="snippets"
			} )
		]])
		exec_lua([[
			ls.add_snippets("all", {
				ls.snippet({trig="triD", snippetType=nil}, {ls.text_node("helloDworld")}, {})
			}, {
				key = "d",
				type="autosnippets"
			} )
		]])
		exec_lua([[
			ls.add_snippets("all", {
				ls.snippet({trig="triE", snippetType="snippet"}, {ls.text_node("helloEworld")}, {})
			}, {
				key = "e",
				type="autosnippets"
			} )
		]])

		-- check if snippet "a" is automatically triggered
		feed("<ESC>cc") -- rewrite line
		feed("triA")
		screen:expect({
			grid = [[
			helloAworld^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<ESC>cc") -- rewrite line
		feed("triB")
		-- check if snippet "b" is NOT automatically triggered
		screen:expect({
			grid = [[
			triB^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- check if snippet "b" is working
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			helloBworld^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<ESC>cc") -- rewrite line
		feed("triC")
		-- check if snippet "c" is NOT automatically triggered
		screen:expect({
			grid = [[
			triC^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- check if snippet "c" is working
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			helloCworld^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<ESC>cc") -- rewrite line
		feed("triD")
		-- check if snippet "d" is automatically triggered
		screen:expect({
			grid = [[
			helloDworld^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<ESC>cc") -- rewrite line
		feed("triE")
		-- check if snippet "e" is NOT automatically triggered
		screen:expect({
			grid = [[
			triE^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- check if snippet "c" is working
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			helloEworld^                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("snippets' filetype overrides add_snippets-filetype", function()
		exec_lua([[
			ls.add_snippets("c", {
				s({trig = "in_lua", filetype = "lua"}, {t"expanded in lua"})
			})
		]])
		exec("set ft=c")
		feed("iin_lua")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			in_lua^                                            |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec("set ft=lua")
		feed("<Cr>in_lua")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			in_lua                                            |
			expanded in lua^                                   |
			{2:-- INSERT --}                                      |]],
		})
	end)

	-- maybe a bit out of place here, but this issue would mainly manifest when invalidating snippets for some key.
	it("replacing snippets via key works for duplicated snippets.", function()
		exec_lua([[
			ls.add_snippets("all", {
				require("luasnip.nodes.duplicate").duplicate_addable(s("asdf", {t"fasd"}))
			}, {key = "asdf"})
		]])
		feed("iasdf")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			fasd^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua([[
			ls.add_snippets("all", {
				require("luasnip.nodes.duplicate").duplicate_addable(s("asdf", {t"asdf"}))
			}, {key = "asdf"})
		]])
		feed("<esc>ccasdf")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			asdf^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
