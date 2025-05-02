local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec
local Screen = require("test.functional.ui.screen")
local assert = require("luassert")

describe("loaders:", function()
	local screen

	local function setup(...)
		ls_helpers.clear()

		ls_helpers.session_setup_luasnip(...)
		screen = ls_helpers.new_screen(50, 8)
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end
	before_each(function()
		setup({ no_snip_globals = true })
	end)

	after_each(function()
		screen:detach()
	end)

	it("error-message when source not available", function()
		ls_helpers.loaders["vscode(rtp)"]()

		feed("iall1")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			expands? jumps? ^  !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<esc>")
		exec_lua(
			[[require("luasnip.extras.snip_location").jump_to_active_snippet()]]
		)
		screen:expect({
			grid = [[
			expands? jumps?^   !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			Snippet does not have a source.                   |]],
		})
	end)

	it("vscode: error-message when parser not installed.", function()
		setup({
			no_snip_globals = true,
			setup_extend = { loaders_store_source = true },
		})
		ls_helpers.loaders["vscode(rtp)"]()

		feed("iall1")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			expands? jumps? ^  !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- immediately clear error-message.
		feed(
			"<esc><cmd>lua require('luasnip.extras.snip_location').jump_to_active_snippet()<Cr><Cr>"
		)
		-- remove error-message for easier version-compatibility (it was changed
		-- somewhere between 0.9 and master at the time of writing).
		screen:expect({
			grid = [[
			^{                                                 |
			        "snip1": {                                |
			                "prefix": "all1",                 |
			                "body": [                         |
			                        "expands? jumps? $1 $2 !" |
			                ]                                 |
			        },                                        |
			                                                  |]],
		})
	end)

	it("snipmate: highlights snippet-definition.", function()
		setup({
			no_snip_globals = true,
			setup_extend = { loaders_store_source = true },
		})
		ls_helpers.loaders["snipmate(rtp)"]()

		feed("iall1")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			expands? jumps? ^  !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<esc>")
		exec_lua(
			[[require("luasnip.extras.snip_location").jump_to_active_snippet()]]
		)
		screen:expect({
			grid = [[
			# A comment                                       |
			{3:^snippet all1 A test snippet}                       |
			{3:        expands? jumps? $1 $2 !}                   |
			snippet all2 Another snippet                      |
			        multi$1                                   |
			        # not removed??                           |
			        line$2                                    |
			                                                  |]],
		})
	end)

	it("vscode: correctly highlights definition if parser installed", function()
		setup({
			no_snip_globals = true,
			setup_extend = { loaders_store_source = true },
			setup_parsers = true,
		})

		ls_helpers.loaders["vscode(rtp)"]()

		feed("iall1")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			expands? jumps? ^  !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<esc>")
		exec_lua(
			[[require("luasnip.extras.snip_location").jump_to_active_snippet()]]
		)
		screen:expect({
			grid = [[
			{                                                 |
			{3:       ^ "snip1": {}                                |
			{3:                "prefix": "all1",}                 |
			{3:                "body": [}                         |
			{3:                        "expands? jumps? $1 $2 !"} |
			{3:                ]}                                 |
			{3:        },}                                        |
			                                                  |]],
		})
	end)

	it(
		"lua: highlights definition (should always work, the lua-parser is installed by default).",
		function()
			setup({
				no_snip_globals = true,
				setup_extend = { loaders_store_source = true },
				setup_parsers = true,
			})
			ls_helpers.loaders["lua(rtp)"]()

			feed("iall1")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
			expands? jumps? ^  !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
			feed("<esc>")
			exec_lua(
				[[require("luasnip.extras.snip_location").jump_to_active_snippet()]]
			)
			screen:expect({
				grid = [[
			return {                                          |
			{3:       ^ s("all1", fmt("expands? jumps? {} {} !", {}|
			{3: i(1), i(2) })),}                                  |
			}, {                                              |
			        parse("auto???", "autotriggered????????"),|
			}                                                 |
			{0:~                                                 }|
			                                                  |]],
			})
		end
	)
end)
