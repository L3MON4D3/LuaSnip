local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("Parser", function()
	local screen

	before_each(function()
		helpers.clear()

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
		ls_helpers.session_setup_luasnip()
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

	it("Omits \\r in passed text.", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"adsf\\r\\nasdf"'

		assert.are.same(
			exec_lua(
				'return ls.parser.parse_snippet("", '
					.. snip
					.. "):get_static_text()"
			),
			{ "adsf", "asdf" }
		)
		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			adsf                                              |
			asdf^                                              |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Can create snippets with tabstops.", function()
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()
		local snip = '"a${TM_LINE_INDEX/(.*)/asdf $1 asdf/g}a"'

		-- /g matches as often as possible, hence two matches, but one with an
		-- empty (eg. without a) group 1.
		ls_helpers.lsp_static_test(
			snip,
			{ "aasdf $TM_LINE_INDEX asdfasdf  asdfa" }
		)

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			aasdf 0 asdfasdf  asdfa^                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("just inserts the variable if jsregexp is not available.", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"a${TM_LINE_INDEX/(.*)/asdf $1 asdf/g}a"'

		-- /g matches as often as possible, hence two matches, but one with an
		-- empty (eg. without a) group 1.
		ls_helpers.lsp_static_test(snip, { "a$TM_LINE_INDEXa" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a0a^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse transformed tabstop.", function()
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()
		local snip = '"$1 a ${1/(.*)/asdf $1 asdf/} a"'

		ls_helpers.lsp_static_test(snip, { " a asdf  asdf a" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^ a asdf  asdf a                                   |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
	it("copies tabstop if jsregexp is not available.", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"$1 a ${1/(.*)/asdf $1 asdf/} a"'

		ls_helpers.lsp_static_test(snip, { " a  a" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^ a  a                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("asdf")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			asdf a asdf a^                                     |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("modifies invalid $0 with choice.", function()
		ls_helpers.session_setup_luasnip()
		-- this can't work in luasnip.
		-- solution: add
		local snip = '"$0   ${0|asdf,qwer,zxcv|} asdf"'

		ls_helpers.lsp_static_test(snip, { "asdf   asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			asdf   ^asdf asdf                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- choice is copied
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
			qwer   ^qwer asdf                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- make sure $0 is actually behind choice.
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			qwer   qwer^ asdf                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("modifies invalid $0 with choice nested in placeholder.", function()
		ls_helpers.session_setup_luasnip()
		-- this can't work in luasnip.
		-- solution: add
		local snip = '"$0   ${1: ${0|asdf,qwer,zxcv|}} asdf"'

		ls_helpers.lsp_static_test(snip, { "asdf    asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			asdf   ^ asdf asdf                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- jump to choice..
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			asdf    ^asdf asdf                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- and to new $0.
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			asdf    asdf^ asdf                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("does not modify $0 which can be represented.", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"${0:qwer} asdf"'

		ls_helpers.lsp_static_test(snip, { "qwer asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^q{3:wer} asdf                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			^q{3:wer} asdf                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("turns the correct nodes into insert/functionNode", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"${1} ${1:asdf} ${1:asdf}"'

		ls_helpers.lsp_static_test(snip, { "asdf asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")

		-- actually not sure if this is how it should be, vscode just spawns
		-- multicursors :(
		screen:expect({
			grid = [[
			asdf ^a{3:sdf} asdf                                    |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("turns the correct nodes into insert/functionNode v2", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"${1} ${1:asdf} ${1|a,b,c,d,e|}"'

		ls_helpers.lsp_static_test(snip, { "asdf asdf asdf" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")

		-- actually not sure if this is how it should be, vscode just spawns
		-- multicursors :(
		screen:expect({
			grid = [[
			asdf ^a{3:sdf} asdf                                    |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("can modify groups in transform.", function()
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()
		local snip = '"$1 a ${1/(.*)/asdf ${1:/upcase} asdf/} a"'

		ls_helpers.lsp_static_test(snip, { " a asdf  asdf a" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^ a asdf  asdf a                                   |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("rrrr")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			rrrr a asdf RRRR asdf a^                           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("handle multiple captures in transform.", function()
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()
		local snip = '"${1:bbb} a ${1/(.)b(.)/${1:/upcase} $2/g} a"'

		ls_helpers.lsp_static_test(snip, { "bbb a B b a" })

		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			^b{3:bb} a B b a                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		feed("bbbbbb")
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			bbbbbb a B bB b a^                                 |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse lazy variables.", function()
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
		local snip = '"a${MISSING_VAR}a"'

		ls_helpers.lsp_static_test(snip, { "a$MISSING_VARa" })
		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a^M{3:ISSING_VAR}a                                     |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("can parse missing user defined variable in placeholder.", function()
		ls_helpers.session_setup_luasnip()
		local snip = '"a${1:$MISSING_VAR}a"'

		ls_helpers.lsp_static_test(snip, { "a$MISSING_VARa" })

		-- Assure this is parsed into choice+insertNode.
		exec_lua("ls.lsp_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			a^MISSING_VARa                                     |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			a^M{3:ISSING_VAR}a                                     |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("can parse user defined variable with namespace.", function()
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
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
		ls_helpers.session_setup_luasnip()
		local snip = "b\n\t$TM_SELECTED_TEXT b"

		-- indent, insert text, SELECT.
		feed("i<Tab><Tab>asdf<Cr>asdf<Esc>Vk<Tab> ")
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		-- the \t is extended to both lines of $TM_SELECTED_TEXT (not just the
		-- first!).
		screen:expect({
			grid = [[
			        asdf                                      |
			        asdf b^                                    |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("indents Variables in placeholder.", function()
		ls_helpers.session_setup_luasnip()
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

	it("Inserts variable as placeholder on unknown varname.", function()
		ls_helpers.session_setup_luasnip()
		local snip = "${A_VARIABLE_DOES_IT_EXIST_QUESTION_MARK}"

		-- indent, insert text, SELECT.
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		-- the \t in front of $1 is extended to both lines of $TM_SELECTED_TEXT.
		screen:expect({
			grid = [[
			^A{3:_VARIABLE_DOES_IT_EXIST_QUESTION_MARK}            |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Inserts default when the variable is empty", function()
		ls_helpers.session_setup_luasnip()
		local snip = "${LS_SELECT_DEDENT: a ${2:default}}"

		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		screen:expect({
			grid = [[
			 a ^d{3:efault}                                        |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("<Esc>ccSELECTED TEXT<Esc>V<Tab>")
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")
		screen:expect({
			grid = [[
			SELECTED TEXT^                                     |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Applies transform to empty variable.", function()
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()
		local snip = "${TM_SELECTED_TEXT/(.*)/ asd /}"

		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		screen:expect({
			grid = [[
			 asd ^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("correctly transforms multiline-values.", function()
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()
		local snip = "${TM_SELECTED_TEXT/([^]*)/a ${1} a/}"

		-- expand snippet with selected multiline-text.
		feed("iasdf<Cr>asdf<Esc>Vk<Tab>")
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		screen:expect({
			grid = [[
			a asdf                                            |
			asdf a^                                            |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("handles default correctly inside placeholder", function()
		ls_helpers.session_setup_luasnip()
		local snip = "${1: ${LS_SELECT_DEDENT: a ${2:default}} }"

		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		-- variable with default is parsed into choice
		screen:expect({
			grid = [[
			^  a default                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			  a ^d{3:efault}                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		exec_lua("ls.change_choice()")
		screen:expect({
			grid = [[
			^                                                  |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("handles copy-source inside default.", function()
		ls_helpers.session_setup_luasnip()
		local snip = "${1: ${LS_SELECT_DEDENT: a ${2:default} ${3:copied}}} $3"

		exec_lua("ls.lsp_expand([[" .. snip .. "]])")

		-- variable with default is parsed into choice
		screen:expect({
			grid = [[
			^  a default copied copied                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.jump(1)")
		exec_lua("ls.jump(1)")
		feed("still copied")
		exec_lua("ls.active_update_dependents()")
		screen:expect({
			grid = [[
			  a default still copied^ still copied             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.change_choice()")
		-- this is somewhat debatable, should the functionNode disappear if
		-- there is no source? Right now it just doesn't update, I think that's
		-- okay.
		screen:expect({
			grid = [[
			^ still copied                                     |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("handles copy inside default", function()
		ls_helpers.session_setup_luasnip()
		local snip = "$1 ${2: ${LS_SELECT_DEDENT: a ${3:default} $1} }"

		-- indent, insert text, SELECT.
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")
		screen:expect({
			grid = [[
			^   a default                                      |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("third_tabstop")

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			third_tabstop ^  a default third_tabstop           |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("can parse vim-stuff in snipmate-snippets.", function()
		ls_helpers.session_setup_luasnip()
		local snip = [["The year is ${1:`'lel' . 'lol'`}"]]

		exec_lua("ls.snip_expand(ls.parser.parse_snipmate('', " .. snip .. "))")
		screen:expect({
			grid = [[
			The year is ^l{3:ellol}                                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("can parse multiple vim-stuff in snipmate-snippets.", function()
		ls_helpers.session_setup_luasnip()
		local snip = [["The year is ${1:`'rrr' . 'adsf'`} ` 'leeeee' . 'l'` "]]

		exec_lua("ls.snip_expand(ls.parser.parse_snipmate('', " .. snip .. "))")
		screen:expect({
			grid = [[
			The year is ^r{3:rradsf} leeeeel                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Correctly parses unescaped characters.", function()
		ls_helpers.setup_jsregexp()
		ls_helpers.session_setup_luasnip()

		local snip = "${} asdf"

		-- indent, insert text, SELECT.
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")
		screen:expect({
			grid = [[
			${} asdf^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>cc")
		snip = "${1: asdf ${\\}}"
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")
		screen:expect({
			grid = [[
			^ {3:asdf ${}}                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		feed("<Esc>cc")
		snip = "${TM_LINE_NUMBER/(.*)/ ${} aaaa/}"
		exec_lua("ls.lsp_expand([[" .. snip .. "]])")
		screen:expect({
			grid = [[
			 ${} aaaa^                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("correctly parses escaped characters.", function()
		ls_helpers.session_setup_luasnip()
		local snip = [["\\`\\`\\` `'abc' . '\\`lel'`"]]

		exec_lua("ls.snip_expand(ls.parser.parse_snipmate('', " .. snip .. "))")
		screen:expect({
			grid = [[
			``` abc\`lel^                                      |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
