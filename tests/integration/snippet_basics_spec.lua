local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require('test.functional.ui.screen')

describe("snippets_basic", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = {bold=true, foreground=Screen.colors.Blue},
			[1] = {bold=true, foreground=Screen.colors.Brown},
			[2] = {bold=true}
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Can expand Snippets via snip_expand", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"the snippet expands"
				}) )
		]])

		-- screen already is in correct state, set `unchanged`.
		screen:expect{grid=[[
			the snippet expands^                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			unchanged=true }
	end)

	it("Can expand Snippets from `all` via <Plug>", function()
		exec_lua([[
			ls.snippets = {
				all = {
					s("snip", {
						t"the snippet expands"
					})
				}
			}
		]])
		feed("isnip<Plug>luasnip-expand-or-jump")
		screen:expect{grid=[[
			the snippet expands^                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	it("Can jump around in simple snippets.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"text", i(1), t"text again", i(2), t"and again"
				}) )
		]])
		screen:expect{grid=[[
			text^text againand again                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
		exec_lua([[
			ls.jump(1)
		]])
		screen:expect{grid=[[
		  texttext again^and again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]]}
		exec_lua([[
			ls.jump(-1)
		]])
		screen:expect{grid=[[
		  text^text againand again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]]}
		exec_lua([[
			ls.jump(1)
			ls.jump(1)
		]])
		screen:expect{grid=[[
		  texttext againand again^                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]]}
	end)

	it("Can jump around in simple snippets via <Plug>.", function()
		exec_lua([[
			ls.snip_expand(
				s("trig", {
					t"text", i(1), t"text again", i(2), t"and again"
				}) )
		]])
		screen:expect{grid=[[
			text^text againand again                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
		feed("<Plug>luasnip-jump-next")
		screen:expect{grid=[[
		  texttext again^and again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]]}
		feed("<Plug>luasnip-jump-prev")
		screen:expect{grid=[[
		  text^text againand again                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]]}
		feed("<Plug>luasnip-jump-next<Plug>luasnip-jump-next")
		screen:expect{grid=[[
		  texttext againand again^                           |
		  {0:~                                                 }|
		  {2:-- INSERT --}                                      |]]}
	end)
end)
