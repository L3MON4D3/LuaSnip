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

	it("can parse transformed variables.", function()
		local snip = '"a${TM_LINE_INDEX/(.*)/asdf $1 asdf/g}a"'

		-- /g matches as often as possible, hence two matches, but one with an
		-- empty (eg. without a) group 1.
		ls_helpers.lsp_static_test(snip, { "aasdf $TM_LINE_INDEX asdfasdf  asdfa" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect{grid=[[
			aasdf 0 asdfasdf  asdfa^                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	it("can parse transformed tabstop.", function()
		local snip = '"$1 a ${1/(.*)/asdf $1 asdf/} a"'

		ls_helpers.lsp_static_test(snip, { " a asdf  asdf a" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect{grid=[[
			^ a asdf  asdf a                                   |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	it("modifies invalid $0 with choice.", function()
		-- this can't work in luasnip.
		-- solution: add
		local snip = '"$0   ${0|asdf,qwer,zxcv|} asdf"'

		ls_helpers.lsp_static_test(snip, { "asdf   asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect{grid=[[
			asdf   ^asdf asdf                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}

		-- choice is copied
		exec_lua("ls.change_choice(1)")
		screen:expect{grid=[[
			qwer   ^qwer asdf                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}

		-- make sure $0 is actually behind choice.
		exec_lua("ls.jump(1)")
		screen:expect{grid=[[
			qwer   qwer^ asdf                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	it("does not modify $0 which can be represented.", function()
		local snip = '"${0:qwer} asdf"'

		ls_helpers.lsp_static_test(snip, { "qwer asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect{grid=[[
			^q{3:wer} asdf                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
		exec_lua("ls.jump(1)")
		screen:expect{grid=[[
			^q{3:wer} asdf                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)

	it("turns the correct nodes into insert/functionNode", function()
		local snip = '"${1} ${1:asdf} ${1:asdf}"'

		ls_helpers.lsp_static_test(snip, { "asdf asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")

		-- actually not sure if this is how it should be, vscode just spawns
		-- multicursors :(
		screen:expect{grid=[[
			asdf ^a{3:sdf} asdf                                    |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)

	it("turns the correct nodes into insert/functionNode v2", function()
		local snip = '"${1} ${1:asdf} ${1|a,b,c,d,e|}"'

		ls_helpers.lsp_static_test(snip, { "asdf asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")

		-- actually not sure if this is how it should be, vscode just spawns
		-- multicursors :(
		screen:expect{grid=[[
			asdf ^a{3:sdf} asdf                                    |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)

	it("can modify groups in transform.", function()
		local snip = '"$1 a ${1/(.*)/asdf ${1:/upcase} asdf/} a"'

		ls_helpers.lsp_static_test(snip, { " a asdf  asdf a" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect{grid=[[
			^ a asdf  asdf a                                   |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
		feed("rrrr")
		exec_lua("ls.jump(1)")
		screen:expect{grid=[[
			rrrr a asdf RRRR asdf a^                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	it("can parse lazy variables.", function()
		local snip = '"a${LINE_COMMENT}a"'

		ls_helpers.lsp_static_test(snip, { "a$LINE_COMMENTa" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a//a^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse user defined variable without namespace.", function()
		local snip = '"a${MISSING_VAR}a"'

		ls_helpers.lsp_static_test(snip, { "a$MISSING_VARa" })
		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			aa^                                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse user defined variable with namespace.", function()
		local snip = '"a${USER_VAR}a"'

		ls_helpers.lsp_static_test(snip, { "a$USER_VARa" })
		exec_lua([[
                ls.env_namespace('USER', {vars={VAR="the content"}})
                ls.lsp_expand(
                ]] .. snip .. ")")
		screen:expect({
			grid = [[
			athe contenta^                                     |
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

	it("indents Variables.", function()
		local snip = "b\n\t$TM_SELECTED_TEXT b"

		-- indent, insert text, SELECT.
		feed("i<Tab><Tab>asdf<Cr>asdf<Esc>Vk<Tab> ")
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		-- the \t in front of $1 is extended to both lines of $TM_SELECTED_TEXT.
		screen:expect({
			grid = [[
			        asdf                                      |
			        asdf b^                                    |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("indents Variables in placeholder.", function()
		local snip = "b\n\t${1:$TM_SELECTED_TEXT}b"

		-- indent, insert text, SELECT.
		feed("i<Tab><Tab>asdf<Cr>asdf<Esc>Vk<Tab> ")
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		-- the \t in front of $1 is extended to both lines of $TM_SELECTED_TEXT.
		screen:expect({
			grid = [[
			        ^a{3:sdf}                                      |
			{3:        asdf}b                                     |
			{2:-- SELECT --}                                      |]],
		})

		-- just make sure this also works.
		snip = "b\n\t$TM_SELECTED_TEXTb"
	end)

	it("can parse vim-stuff in snipmate-snippets.", function()
		local snip = [["The year is ${1:`'lel' . 'lol'`}"]]

		exec_lua("ls.snip_expand(ls.parser.parse_snipmate('', " .. snip .. "))")
		screen:expect{grid=[[
			The year is ^l{3:ellol}                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)

	it("can parse multiple vim-stuff in snipmate-snippets.", function()
		local snip = [["The year is ${1:`'rrr' . 'adsf'`} ` 'leeeee' . 'l'` "]]

		exec_lua("ls.snip_expand(ls.parser.parse_snipmate('', " .. snip .. "))")
		screen:expect{grid=[[
			The year is ^r{3:rradsf} leeeeel                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)
end)
