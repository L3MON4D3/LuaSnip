local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("Parser", function()
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

	it("Expands text-only snippet with auto-generated $0.", function()
		local snip = '"abcde"'

		assert.are.same(
			exec_lua(
				'return ls.parser.parse_snippet("", '
					.. snip
					.. "):get_static_text()"
			),
			{ "abcde" }
		)
		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			abcde^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Can create snippets with tabstops.", function()
		local snip = '"a$2 $0b$1 c"'

		assert.are.same(
			exec_lua(
				'return ls.parser.parse_snippet("", '
					.. snip
					.. "):get_static_text()"
			),
			{ "a b c" }
		)
		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a b^ c                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a^ b c                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a ^b c                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Can mirror tabstops.", function()
		local snip = '"a$1 ${2:b} c"'

		assert.are.same(
			exec_lua(
				'return ls.parser.parse_snippet("", '
					.. snip
					.. "):get_static_text()"
			),
			{ "a b c" }
		)

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a^ b c                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("dd")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			add ^b c                                           |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("ee")
		exec_lua("ls.jump(-1)")
		screen:expect({
			grid = [[
			a^d{3:d} ee c                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			add ^e{3:e} c                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("can create nested snippets.", function()
		local snip = '"${1: aaa $2 bbb}"'

		assert.are.same(
			exec_lua(
				'return ls.parser.parse_snippet("", '
					.. snip
					.. "):get_static_text()"
			),
			{ " aaa  bbb" }
		)

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^ aaa  bbb                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			 aaa ^ bbb                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- this may need to be adjusted if nested snippets are not created
		-- using choiceNode.
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			^                                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse variables.", function()
		local snip = '"a${TM_LINE_INDEX}a"'

		ls_helpers.lsp_static_test(snip, { "a$TM_LINE_INDEXa" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a0a^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse variables as placeholder.", function()
		local snip = '"a${1:$TM_LINE_INDEX}a"'

		ls_helpers.lsp_static_test(snip, { "a$TM_LINE_INDEXa" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		-- line index should be selected!
		screen:expect({
			grid = [[
			a^0a                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("can parse variables and tabstops nested in placeholder.", function()
		local snip = '"a${1: $2 $TM_LINE_INDEX}a"'

		ls_helpers.lsp_static_test(snip, { "a  $TM_LINE_INDEXa" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a^  0a                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			a^a                                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			a^  0a                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a ^ 0a                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a  0a^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
