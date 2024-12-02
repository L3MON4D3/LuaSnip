local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec
local Screen = require("test.functional.ui.screen")

describe("snippet-ft tooling", function()
	local screen

	before_each(function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = ls_helpers.new_screen(50, 30)
		screen:set_default_attr_ids({
			[0] = { bold = false, foreground = Screen.colors.Gray0 },
			[1] = { foreground = Screen.colors.Cyan1 },
			[2] = { foreground = Screen.colors.Red1 },
			[3] = { foreground = Screen.colors.LightRed },
			[4] = { foreground = Screen.colors.WebGrey },
			[5] = { foreground = Screen.colors.Yellow1 },
			[6] = { foreground = Screen.colors.Magenta1 },
			[7] = { bold = true, foreground = Screen.colors.Blue1 },
			[8] = {
				foreground = Screen.colors.Blue4,
				background = Screen.colors.LightGray,
			},
		})
		exec([[
			hi Identifier guifg=Red
			hi Comment guifg=Green
			hi String guifg=Blue
			hi Keyword guifg=Cyan
			hi SpecialChar guifg=Magenta
			hi Special guifg=Yellow
			hi String guifg=Gray
			hi Error guifg=Orange
			hi Number guifg=LightRed

			syntax on
		]])
	end)

	after_each(function()
		screen:detach()
	end)

	it("syntax works as expected", function()
		exec(
			("edit %s"):format(
				os.getenv("LUASNIP_SOURCE") .. "/tests/data/syntaxtest.snippets"
			)
		)

		exec(
			("source %s/syntax/snippets.vim"):format(
				os.getenv("LUASNIP_SOURCE")
			)
		)

		screen:expect({
			grid = [[
				{1:^extends}{2: lua}                                       |
				                                                  |
				{1:priority}{2: }{3:2000}                                     |
				{1:autosnippet}{2: hello }{4:"Comment"}                       |
				        Hello World! :)                           |
				                                                  |
				{1:snippet}{2: asdf }{4:comment}                              |
				        0qwer                                     |
				        {5:$1} qwer {5:${2:hjkl}}                         |
				        {6:\\}d                                       |
				        1qwer                                     |
				        2qwer                                     |
				                                                  |
				{1:snippet}{2: qwer}                                      |
				    asdf                                          |
				    asdf                                          |
				    asdf                                          |
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				                                                  |]],
		})
	end)

	it("folding works as expected", function()
		exec(
			("edit %s"):format(
				os.getenv("LUASNIP_SOURCE") .. "/tests/data/syntaxtest.snippets"
			)
		)

		exec(
			("source %s/ftplugin/snippets.vim"):format(
				os.getenv("LUASNIP_SOURCE")
			)
		)
		exec(
			("source %s/syntax/snippets.vim"):format(
				os.getenv("LUASNIP_SOURCE")
			)
		)

		exec("set foldenable foldlevel=99")
		feed("zM")

		screen:expect({
			grid = [[
				{1:^extends}{2: lua}                                       |
				                                                  |
				{1:priority}{2: }{3:2000}                                     |
				{8:+--  3 lines: autosnippet hello "Comment"·········}|
				{8:+--  7 lines: snippet asdf comment················}|
				{8:+--  4 lines: snippet qwer························}|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				{7:~                                                 }|
				                                                  |]],
		})
	end)
end)
