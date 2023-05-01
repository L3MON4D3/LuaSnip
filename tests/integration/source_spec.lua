local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")
local assert = require("luassert")

describe("loaders:", function()
	local screen

	before_each(function()
		helpers.clear()

		screen = Screen.new(50, 8)
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

	it("error-message when source not available", function()
		ls_helpers.session_setup_luasnip({ no_snip_globals = true })
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
		ls_helpers.session_setup_luasnip({
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
		feed("<esc>")
		exec_lua(
			[[require("luasnip.extras.snip_location").jump_to_active_snippet()]]
		)
		screen:expect({
			grid = [[
			^{                                                 |
			        "snip1": {                                |
			                "prefix": "all1",                 |
			                "body": [                         |
			                        "expands? jumps? $1 $2 !" |
			                ]                                 |
			        },                                        |
			Could not determine ran...help treesitter-parsers |]],
		})
	end)

	it("snipmate: highlights snippet-definition.", function()
		ls_helpers.session_setup_luasnip({
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
		ls_helpers.session_setup_luasnip({
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
			ls_helpers.session_setup_luasnip({
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
