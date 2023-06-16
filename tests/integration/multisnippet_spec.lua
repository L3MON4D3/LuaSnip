local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("multisnippets", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()
		exec_lua([[
			ms = require("luasnip.nodes.multiSnippet").new_multisnippet
			add_ms = function(...)
				ls.add_snippets("all", {
					ms(...)
				}, {key = "ms"})
			end
		]])

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

	it("work at all", function()
		exec_lua([[
			add_ms({"a", "b", "c", "d"}, {t"a or b or c or d"})
		]])
		local function test()
			screen:expect({
				grid = [[
				a or b or c or d^                                  |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end

		feed("ia<Plug>luasnip-expand-or-jump")
		test()
		feed("<Esc>ccb<Plug>luasnip-expand-or-jump")
		test()
		feed("<Esc>ccc<Plug>luasnip-expand-or-jump")
		test()
		feed("<Esc>ccd<Plug>luasnip-expand-or-jump")
		test()
		-- can expand multiple at once.
		feed(
			"<Esc>cca<Plug>luasnip-expand-or-jump<Space>b<Plug>luasnip-expand-or-jump"
		)
		screen:expect({
			grid = [[
			a or b or c or d a or b or c or d^                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua([[
			m_snip = ms({"a", "b", "c", "d"}, {t"a or b or c or d"})
			for _, snip in ipairs(m_snip:retrieve_all()) do
				assert(snip:get_docstring()[1] == "a or b or c or d$0", "get_docstring works")
				assert(snip:copy() ~= snip:copy(), "copy produces new snippet")
			end
		]])
	end)

	it("can merge string-context with table-context", function()
		exec_lua([[
			ls.setup({enable_autosnippets = true})
			add_ms({{trig="a",snippetType="autosnippet"}, "b", "c", "d"}, {t"a or b or c or d"})
		]])
		local function test()
			screen:expect({
				grid = [[
				a or b or c or d^                                  |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end
		-- autotriggered!
		feed("ia")
		test()
		feed("<Esc>ccb<Plug>luasnip-expand-or-jump")
		test()
		feed("<Esc>ccc<Plug>luasnip-expand-or-jump")
		test()
		feed("<Esc>ccd<Plug>luasnip-expand-or-jump")
		test()
	end)

	it("respects `common` context", function()
		exec_lua([[
			ls.setup({enable_autosnippets = true})
			add_ms({common={trig="a",snippetType="autosnippet"}, "b", "c", {snippetType="snippet"}}, {t"a or b or c or d"})
		]])
		local function test()
			screen:expect({
				grid = [[
				a or b or c or d^                                  |
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end
		feed("ia<Plug>luasnip-expand-or-jump")
		test()
		feed("<Esc>ccb")
		test()
		feed("<Esc>ccc")
		test()
	end)

	it("respects `opts`", function()
		exec_lua([[
			ls.setup({enable_autosnippets = true})
			ls.__did_expand = false
			add_ms({"a", "b"}, {t"a or b or c or d"}, {
				common_opts = {
					callbacks = {
						[-1] = {
							[events.pre_expand] = function()
								ls.__did_expand = true
							end
						}
					}
				}
			})
		]])
		feed("ia")
		exec_lua([[
			ls.expand()
			assert(ls.__did_expand)
		]])

		feed("<Esc>ccb")
		exec_lua([[
			ls.__did_expand = false
			ls.expand()
			assert(ls.__did_expand)
		]])
	end)

	it("work with extend_decorator", function()
		ls_helpers.session_setup_luasnip({
			setup_extend = { enable_autosnippets = true },
		})

		exec_lua([[
			-- contexts without trigger get "asdf", add one context which has
			-- the default-trigger and is an autosnippet.
			local auto_multisnippet = ls.extend_decorator.apply(ls.multi_snippet, {common = "asdf", {snippetType = "autosnippet"}})

			ls.add_snippets("all", {
				auto_multisnippet({"bsdf"}, {t"csdf"})
			}, {key = "asdf"})
		]])
		feed("iasdf")
		screen:expect({
			grid = [[
			csdf^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Cr>bsdf")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			csdf                                              |
			csdf^                                              |
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
