local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("Jumping", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 5)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
			[4] = {
				background = Screen.colors.LightGrey,
				foreground = Screen.colors.DarkBlue,
			},
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Folds are opened when jumped into", function()
		local snip = [[
			s("aug", {
				t("augroup "),
				i(1, "GroupName"),
				t({ "AuGroup", "\t" }),
				t({ "au!", "\tau " }),
				i(2, "CursorHold * redrawstatus"),
				i(0),
				t({ "", "augroup end" }),
			})
		]]

		helpers.exec("set foldenable foldmethod=manual")

		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
            augroup ^G{3:roupName}AuGroup                          |
                    au!                                       |
                    au CursorHold * redrawstatus              |
            augroup end                                       |
            {2:-- SELECT --}                                      |
        ]],
		})

		-- fold middle-lines.
		feed("<Esc>jzfj")
		screen:expect({
			grid = [[
            augroup GroupNameAuGroup                          |
            {4:^+--  2 lines: au!·································}|
            augroup end                                       |
            {0:~                                                 }|
                                                              |
        ]],
		})

		-- folded lines are opened correctly when jumped into them.
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
          augroup GroupNameAuGroup                          |
                  au!                                       |
                  au ^C{3:ursorHold * redrawstatus}              |
          augroup end                                       |
          {2:-- SELECT --}                                      |
        ]],
		})
	end)

	it("jumps correctly when multibyte-characters are present.", function()
		local snip = [[
			s("trig", {
				t{"asdf", "핓s㕥f"}, i(1, "asdf"),
				t{"", "asdf"}, i(2, "핓sdf"),
			})
		]]

		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
            asdf                                              |
            핓s㕥f^a{3:sdf}                                        |
            asdf핓sdf                                         |
            {0:~                                                 }|
            {2:-- SELECT --}                                      |
        ]],
		})

		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
            asdf                                              |
            핓s㕥fasdf                                        |
            asdf^핓{3:sdf}                                         |
            {0:~                                                 }|
            {2:-- SELECT --}                                      |
        ]],
		})
	end)

	it("can restore the cursor position.", function()
		local snip = [[
			s("res", {
				c(1, {
					{
						i(1), t{"aa", "aa "}, r(2, "key", i(1))
					},
					{
						i(1), t" aa", r(2, "key"),
					},
					{
						i(1, "insert"), t{"aa", "aa", "aa"}, r(2, "key")
					}
				}, {restore_cursor = true})
			})
		]]

		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
            ^aa                                                |
            aa                                                |
            {0:~                                                 }|
            {0:~                                                 }|
            {2:-- INSERT --}                                      |
        ]],
		})

		-- jump into restoreNode in first choice.
		exec_lua("ls.jump(1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
             aa^                                               |
            {0:~                                                 }|
            {0:~                                                 }|
            {0:~                                                 }|
            {2:-- INSERT --}                                      |
        ]],
		})

		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
            insertaa                                          |
            aa                                                |
            aa^                                                |
            {0:~                                                 }|
            {2:-- INSERT --}                                      |
        ]],
		})

		-- into first of third choice and change, should end up in first of
		-- first choice.
		exec_lua("ls.jump(-1)")
		exec_lua("ls.change_choice(1)")
		screen:expect({
			grid = [[
            ^aa                                                |
            aa                                                |
            {0:~                                                 }|
            {0:~                                                 }|
            {2:-- INSERT --}                                      |
        ]],
		})
	end)

	it("can leave the snippet using region_check_events", function()
		local snip = [[
			s("res", {
				i(1, "a"), i(2, "b"), i(3, "c"), i(4, "d")
			})
		]]

		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
            ^abcd                                              |
            {0:~                                                 }|
            {0:~                                                 }|
            {0:~                                                 }|
            {2:-- SELECT --}                                      |
        ]],
		})

		-- leave region of snippet and assure that it is left (by jumping once
		-- and asserting that the cursor doesn't move) after calling
		-- ls.exit_out_of_region() (the function called by region_check_events).
		feed("<Esc>o")
		exec_lua(
			"ls.exit_out_of_region(ls.session.current_nodes[vim.api.nvim_get_current_buf()])"
		)
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
            abcd                                              |
            ^                                                  |
            {0:~                                                 }|
            {0:~                                                 }|
            {2:-- INSERT --}                                      |
        ]],
		})
	end)
end)
