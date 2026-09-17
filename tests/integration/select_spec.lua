local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec
local Screen = require("test.functional.ui.screen")

describe("Selection", function()
	local screen

	before_each(function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = ls_helpers.new_screen(50, 7)
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

	it("works via config-keybinding, and does not alter registers.", function()
		exec_lua("regs_pre = vim.api.nvim_get_context({}).regs")

		feed("iasdf qwer<Esc>v^<Tab>")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			.asdf qwer.^                                       |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		assert.is_true(
			exec_lua(
				"return vim.deep_equal(vim.api.nvim_get_context({}).regs, regs_pre)"
			)
		)
	end)

	it("works via manual keybinding (deprecated api).", function()
		exec_lua([[
			vim.keymap.set({"x"}, "p", ls.select_keys, {silent = true})
		]])
		feed("iasdf qwer<Esc>v^p")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			.asdf qwer.^                                       |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
	it("works via manual keybinding.", function()
		exec_lua([[
			vim.keymap.set({"x"}, "p", ls.cut_keys, {silent = true})
		]])
		feed("iasdf qwer<Esc>v^p")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			.asdf qwer.^                                       |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
	it("works via manual custom keybinding.", function()
		exec_lua([=[
			vim.keymap.set({"x"}, "y", [[<Esc><cmd>lua ls.pre_yank("d")<cr>gv"dy<cmd>lua ls.post_yank("d")<cr>]], {silent = true})
		]=])
		feed("iasdf qwer<Esc>v^y")
		screen:expect({
			grid = [[
				^asdf qwer                                         |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				                                                  |]],
		})
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
				.asdf qwer.^asdf qwer                              |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
		})
	end)

	it("works with linewise-selection.", function()
		feed("iasdf qwer<Cr>asdf qwer<Cr>asdf qwer<Esc>Vkk<Tab>")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			.asdf qwer                                        |
			asdf qwer                                         |
			asdf qwer.^                                        |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("works with block-select.", function()
		feed("iasdf qwer<Cr>asdf qwer<Cr>asdf qwer")
		screen:expect({
			grid = [[
			asdf qwer                                         |
			asdf qwer                                         |
			asdf qwer^                                         |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<Esc><C-V>^kkllohh")
		screen:expect({
			grid = [[
			as{3:df qw}er                                         |
			as{3:df qw}er                                         |
			as{3:df q}^wer                                         |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- VISUAL BLOCK --}                                |]],
		})
		feed("<Tab>")
		feed("<Esc>Go")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			aser                                              |
			aser                                              |
			aser                                              |
			.df qw                                            |
			df qw                                             |
			df qw.^                                            |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("works with virtualedit.", function()
		feed(":set virtualedit=block<Cr>")
		feed("iasdf qwer<Cr>asdf qwer<Cr>asdf qwer")
		feed("<Esc><C-V>kkllll")
		screen:expect({
			grid = [[
			asdf qwe{3:r   }^                                      |
			asdf qwe{3:r    }                                     |
			asdf qwe{3:r    }                                     |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- VISUAL BLOCK --}                                |]],
		})
		feed("<Tab>")
		feed("<Esc>Go")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			asdf qwe                                          |
			asdf qwe                                          |
			asdf qwe                                          |
			.r                                                |
			r                                                 |
			r    .^                                            |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("works for multibyte characters.", function()
		feed("i   𝔼f-𝔼abc<Esc>vbb")
		screen:expect({
			grid = [[
			   𝔼f^-{3:𝔼abc}                                        |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- VISUAL --}                                      |]],
		})
		feed("<Tab>")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			   𝔼f.-𝔼abc.^                                      |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("works for combined characters.", function()
		feed("i   ‖͚asdf‖͚qwer<Esc>vbbh")
		screen:expect({
			grid = [[
			   ‖͚asd^f{3:‖͚qwer}                                     |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- VISUAL --}                                      |]],
		})
		feed("<Tab>")
		exec_lua([[ls.lsp_expand(".$LS_SELECT_RAW.")]])
		screen:expect({
			grid = [[
			   ‖͚asd.f‖͚qwer.^                                   |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	-- Name, selection keys, expected dedented text.
	for _, case in ipairs({
		{
			"preserves interior whitespace in characterwise selections",
			"gg^vjj$",
			{ "first    gap", "  keep    gap", "last    gap" },
		},
		{ "respects single-line selection bounds", "gg01lv6l", { "firs" } },
		{ "dedents selected indentation", "gg0v2l", { "" } },
		{ "preserves selected interior spaces", "gg09lv3l", { "    " } },
	}) do
		it(case[1], function()
			exec_lua([[
				vim.api.nvim_buf_set_lines(0, 0, -1, true, {
					"    first    gap", "      keep    gap", "    last    gap",
				})
			]])
			feed(case[2] .. "<Tab>")
			ls_helpers.assert.eq(
				case[3],
				exec_lua("return vim.b.LUASNIP_SELECT_DEDENT")
			)
		end)
	end

	it("does not destroy any registers.", function() end)
end)
