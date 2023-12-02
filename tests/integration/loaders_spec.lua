local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")
local assert = require("luassert")

local function for_all_loaders(message, fn)
	for name, load in pairs(ls_helpers.loaders) do
		it(name .. " " .. message, function()
			-- needed for snipmate-loader.
			load("snippets")
			-- triggers actual load for `lazy_load()`s'
			exec("doautocmd Filetype")
			fn()
		end)
	end
end

describe("loaders:", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip({ no_snip_globals = true })

		ls_helpers.scratch_prepare()

		screen = Screen.new(50, 5)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end)

	after_each(function()
		ls_helpers.scratch_clear()

		screen:detach()
	end)

	local function reload_test(message, load_fn, snippet_file, edit_keys)
		it(message, function()
			load_fn()

			-- check unmodified.
			feed("iall1")
			exec_lua("ls.expand()")

			screen:expect({
				grid = [[
				expands? jumps? ^  !                               |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})

			-- edit snippet-file to ensure hot-reload works.
			exec(([[
				edit %s
			]]):format(os.getenv("LUASNIP_SOURCE") .. snippet_file))

			-- edit snippet-file, and check for reload.
			feed(edit_keys)

			feed("<Esc>:w<Cr>")
			exec_lua("vim.wait(10, function() end)")
			feed("<C-O>ccall1")

			exec_lua("ls.expand()")

			-- undo changes to snippet-file before checking results.
			feed("<Esc><C-I>u:w<Cr><C-O>")

			-- re-enter current placeholder
			exec_lua("ls.jump(-1)")
			exec_lua("ls.jump( 1)")

			screen:expect({
				grid = [[
				replaces? jumps? ^  !                              |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end)
	end

	for_all_loaders("loads `all`-(autotriggered) snippet", function()
		-- expand loaded snippet manually.
		feed("iall1")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			expands? jumps? ^  !                               |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- every loader has exactly one lua-autosnippet. Make sure it's loaded.
		assert.are.same(
			1,
			exec_lua(
				[[return #ls.get_snippets("all", {type = "autosnippets"})]]
			)
		)
	end)

	it("Can lazy-load from multiple sources", function()
		ls_helpers.loaders["snipmate(lazy)"]("snippets")
		ls_helpers.loaders["vscode(lazy)"]()
		ls_helpers.loaders["lua(lazy)"]()
		-- triggers actual load for `lazy_load()`s'
		exec("set ft=lua")
		-- wait a bit for async-operations to finish
		exec('call wait(200, "0")')
		-- one snippet from snipmate, one from vscode.
		assert.are.same(3, exec_lua('return #ls.get_snippets("lua")'))
	end)

	it("Can lazy-load from multiple snipmate-collections.", function()
		ls_helpers.loaders["snipmate(lazy)"]("snippets")
		ls_helpers.loaders["snipmate(lazy)"]("snippets1")
		exec("set ft=lua")
		-- triggers actual load for `lazy_load()`s'
		-- wait a bit for async-operations to finish
		exec('call wait(200, "0")')
		-- one snippet from snippets, another from snippets1.
		assert.are.same(2, exec_lua('return #ls.get_snippets("lua")'))
	end)

	it("Can load with extends (snipmate)", function()
		ls_helpers.loaders["snipmate(lazy)"]("snippets")
		-- triggers actual load for `lazy_load()`s'
		exec("set ft=vim")
		-- wait a bit for async-operations to finish
		exec('call wait(200, "0")')
		-- one snippet from vim.snippets, one from lua.snippets
		assert.are.same(2, exec_lua('return #ls.get_snippets("vim")'))
	end)

	it("separates snippets from different collection for `extends`", function()
		-- load from both snippets (where vim extends lua) and snippets1 (where
		-- it doesn't).
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({paths={"%s", "%s"}})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/snippets",
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/snippets1"
			)
		)

		assert.are.same(3, exec_lua('return #ls.get_snippets("vim")'))
	end)

	it("loads paths with invalid paths ditched (vscode)", function()
		exec_lua(string.format(
			[[require("luasnip.loaders.from_vscode").load({paths={"%s", "%s"}})]],
			os.getenv("LUASNIP_SOURCE") .. "/tests/data/invalid-not-exists",
			os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets" -- has 5 prio snippets
		))

		assert.are.same(5, exec_lua('return #ls.get_snippets("prio")'))
	end)

	it("loads paths with invalid paths ditched (lua)", function()
		exec_lua(string.format(
			[[require("luasnip.loaders.from_lua").load({paths={"%s", "%s"}})]],
			os.getenv("LUASNIP_SOURCE") .. "/tests/data/invalid-not-exists",
			os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/lua-snippets/luasnippets" -- has 1 prio snippet
		))

		assert.are.same(1, exec_lua('return #ls.get_snippets("prio")'))
	end)

	it("respects {override,default}_priority", function()
		-- just the filetype the test-snippets are added for.
		exec("set ft=prio")

		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({
					paths={"%s"},
					override_priority = 2000
				})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/snippets"
			)
		)

		feed("iaaaa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			snipmate^                                          |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua(string.format(
			[[require("luasnip.loaders.from_vscode").load({
					paths={"%s"},
					override_priority = 3000
				})]],
			os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
		))

		feed("<Cr>aaaa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			snipmate                                          |
			vscode^                                            |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({
					paths={"%s"},
					override_priority = 4000
				})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/snippets"
			)
		)

		feed("<Cr>aaaa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			snipmate                                          |
			vscode                                            |
			snipmate^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").load({
					paths={"%s"},
					default_priority = 5000
				})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets"
			)
		)

		feed("<Cr>aaaa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			snipmate                                          |
			vscode                                            |
			snipmate                                          |
			lua^                                               |
			{2:-- INSERT --}                                      |]],
		})

		-- make sure that not just the last loaded snippet is triggered.
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({
					paths={"%s"},
					default_priority = 4999
				})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/snippets"
			)
		)

		feed("<Cr>aaaa")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			vscode                                            |
			snipmate                                          |
			lua                                               |
			lua^                                               |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("vscode-options work.", function()
		ls_helpers.loaders["vscode(rtp)"]()
		exec("set ft=prio")

		feed("ibbbb")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			2^                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua(string.format(
			[[require("luasnip.loaders.from_vscode").load({
					paths={"%s"},
					default_priority = 2002
				})]],
			os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
		))

		feed("<Cr>bbbb")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			2                                                 |
			3^                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("snipmate-options work.", function()
		ls_helpers.loaders["snipmate(rtp)"]()
		exec("set ft=prio")

		feed("ibbbb")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			2^                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({
					paths={"%s"},
					default_priority = 2002
				})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/snippets"
			)
		)

		feed("<Cr>bbbb")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			2                                                 |
			3^                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Can load jsonc.", function()
		ls_helpers.loaders["vscode(rtp)"]()

		feed("ijsonc")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			jsonc!!!^                                          |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	reload_test(
		"snipmate-reload works",
		ls_helpers.loaders["snipmate(rtp)"],
		"/tests/data/snipmate-snippets/snippets/all.snippets",
		"<Esc>2jwcereplaces"
	)

	reload_test(
		"vscode-reload works",
		ls_helpers.loaders["vscode(rtp)"],
		"/tests/data/vscode-snippets/snippets/all.json",
		"<Esc>4jwlcereplaces"
	)
	reload_test(
		"vscode-standalone-reload works",
		ls_helpers.loaders["vscode(standalone)"],
		"/tests/data/vscode-standalone.code-snippets",
		"<Esc>11jwlcereplaces"
	)

	reload_test(
		"lua-reload works",
		ls_helpers.loaders["lua(rtp)"],
		"/tests/data/lua-snippets/luasnippets/all.lua",
		"<Esc>jfecereplaces"
	)

	reload_test(
		"snipmate-reload: load symlinked and edit real",
		function()
			exec_lua(
				string.format(
					[[require("luasnip.loaders.from_snipmate").lazy_load({paths="%s"})]],
					os.getenv("LUASNIP_SOURCE")
						.. "/tests/symlinked_data/snipmate-snippets/snippets"
				)
			)
		end,
		"/tests/data/snipmate-snippets/snippets/all.snippets",
		"<Esc>2jwcereplaces"
	)

	reload_test("vscode-reload: load symlinked and edit real", function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_vscode").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/symlinked_data/vscode-snippets"
			)
		)
	end, "/tests/data/vscode-snippets/snippets/all.json", "<Esc>4jwlcereplaces")

	reload_test("lua-reload: load symlinked and edit real", function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/symlinked_data/lua-snippets/luasnippets"
			)
		)
	end, "/tests/data/lua-snippets/luasnippets/all.lua", "<Esc>jfecereplaces")

	reload_test(
		"snipmate-reload: load real and edit symlinked",
		function()
			exec_lua(
				string.format(
					[[require("luasnip.loaders.from_snipmate").lazy_load({paths="%s"})]],
					os.getenv("LUASNIP_SOURCE")
						.. "/tests/data/snipmate-snippets/snippets"
				)
			)
		end,
		"/tests/symlinked_data/snipmate-snippets/snippets/all.snippets",
		"<Esc>2jwcereplaces"
	)

	reload_test(
		"vscode-reload: load real and edit symlinked",
		function()
			exec_lua(
				string.format(
					[[require("luasnip.loaders.from_vscode").lazy_load({paths="%s"})]],
					os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
				)
			)
		end,
		"/tests/symlinked_data/vscode-snippets/snippets/all.json",
		"<Esc>4jwlcereplaces"
	)

	reload_test(
		"lua-reload: load real and edit symlinked",
		function()
			exec_lua(
				string.format(
					[[require("luasnip.loaders.from_lua").lazy_load({paths="%s"})]],
					os.getenv("LUASNIP_SOURCE")
						.. "/tests/data/lua-snippets/luasnippets"
				)
			)
		end,
		"/tests/symlinked_data/lua-snippets/luasnippets/all.lua",
		"<Esc>jfecereplaces"
	)

	---
	--- Many of the following test will do weird things, like write more than
	--- once, and wait quite often. The delays are added to allow the eventloop
	--- (I guess) to catch up, and process all the autocommands or callbacks
	--- dispatched by the writes.
	--- Multiple writes are sometimes necessary because after the first write,
	--- for some reason, a function called in BufWritePost does not read the
	--- new file contents.
	---
	--- I've never encountered either of these issues in normal usage, so I'm
	--- guessing that they are somehow caused by the testing-framework.
	---

	it("Can load files with `code-snippets`-extension.", function()
		ls_helpers.loaders["vscode(rtp)"]()

		feed("icodesnippets")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			code-snippets!!!^                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Respects `scope` (vscode)", function()
		ls_helpers.loaders["vscode(rtp)"]()

		feed("icc")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			cc^                                                |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec("set ft=c")
		feed("<Cr>cc")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			cc                                                |
			3^                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- check if invalidation affects the duplicated snippet.
		exec_lua([[ls.get_snippets("c")[1]:invalidate()]])
		feed("<Cr>cc")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			cc                                                |
			3                                                 |
			cc^                                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec("set ft=cpp")
		feed("<Cr>cc")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			cc                                                |
			3                                                 |
			cc                                                |
			3^                                                 |
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("lazy registration works for lua.", function()
		exec_lua(([[
			require("luasnip.loaders.from_lua").load({lazy_paths="%s"})
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))

		ls_helpers.scratch_edit("snippets/all.lua")

		feed([[ireturn { ls.parser.parse_snippet("asdf", "qwer") }]])
		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", "qwer") }|
			{0:^~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>:w<Cr>")

		feed("oasdf")
		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", "qwer") }|
			asdf^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", "qwer") }|
			qwer^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("reload_file for manual updates works.", function()
		-- register loader s.t. no automatic updates are received.
		exec_lua(([[
			require("luasnip.loaders.from_lua").load({ lazy_paths="%s", fs_event_providers = {libuv = false, autocmd = false} })
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))

		ls_helpers.scratch_edit("snippets/all.lua")

		feed([[ireturn { ls.parser.parse_snippet("asdf", "qwer") }]])
		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", "qwer") }|
			{0:^~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>:w<Cr>")
		feed("<Esc>:w<Cr>")
		feed("<Esc>:w<Cr>")
		exec_lua("vim.wait(100, function() end)")

		feed("oasdf")
		exec_lua("ls.expand()")
		-- not loaded automatically.
		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", "qwer") }|
			asdf^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>dd:w<Cr>")
		feed(":w<Cr>")

		exec_lua(
			([[require("luasnip.loaders").reload_file("%s")]]):format(
				ls_helpers.scratchdir_path .. "/snippets/all.lua"
			)
		)

		feed("oasdf")
		exec_lua("ls.expand()")

		-- expands after reload_file.
		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", "qwer") }|
			qwer^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("lazy registration works for snipmate.", function()
		exec_lua(([[
			require("luasnip.loaders.from_snipmate").load({lazy_paths="%s"})
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))

		ls_helpers.scratch_edit("snippets/all.snippets")

		feed([[isnippet asdf<Cr>    qwer]])
		screen:expect({
			grid = [[
			snippet asdf                                      |
			    qwer^                                          |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>:w<Cr>")

		feed("oasdf")
		screen:expect({
			grid = [[
			snippet asdf                                      |
			    qwer                                          |
			asdf^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			snippet asdf                                      |
			    qwer                                          |
			qwer^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("lazy registration works for vscode (packages).", function()
		exec_lua(([[
			require("luasnip.loaders.from_vscode").load({lazy_paths="%s"})
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))

		-- double as quick test for package.jsonc
		ls_helpers.scratch_edit("snippets/package.jsonc")

		feed(
			[[i{ "name": "snippets", "contributes": { "snippets": [{"language": ["all"], "path": "./all.json"}] } }]]
		)
		feed("<Esc>:w<Cr>")
		feed("<Esc>:w<Cr>")
		feed("<Esc>:w<Cr>")
		exec_lua("vim.wait(100, function() end)")

		screen:expect({
			grid = [[
			{ "name": "snippets", "contributes": { "snippets":|
			 [{"language": ["all"], "path": "./all.json"}] } ^}|
			{0:~                                                 }|
			{0:~                                                 }|
			<scratch/snippets/package.jsonc" 1L, 101B written |]],
		})

		ls_helpers.scratch_edit("snippets/all.json")

		feed([[i{"snip": {"prefix": "asdf", "body": ["qwer"]}}]])
		feed("<Esc>:w<Cr>")
		feed("<Esc>:w<Cr>")
		feed("<Esc>:w<Cr>")
		exec_lua("vim.wait(100, function() end)")

		screen:expect({
			grid = [[
			{"snip": {"prefix": "asdf", "body": ["qwer"]}^}    |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			<tests/scratch/snippets/all.json" 1L, 47B written |]],
		})

		feed("oasdf")
		exec_lua("ls.expand()")

		screen:expect({
			grid = [[
			{"snip": {"prefix": "asdf", "body": ["qwer"]}}    |
			qwer^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it(
		"lazy registration works for vscode (standalone .code-snippets).",
		function()
			exec_lua(
				([[
			require("luasnip.loaders.from_vscode").load_standalone({path = "%s", lazy = true})
		]]):format(
					ls_helpers.scratchdir_path .. "/vs/snips.code-snippets"
				)
			)

			ls_helpers.scratch_edit("vs/snips.code-snippets")

			feed([[i{"snip": {"prefix": "asdf", "body": ["qwer"]}}]])
			feed("<Esc>:w<Cr>")
			feed("<Esc>:w<Cr>")
			exec_lua("vim.wait(100, function() end)")

			screen:expect({
				grid = [[
			{"snip": {"prefix": "asdf", "body": ["qwer"]}^}    |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			</scratch/vs/snips.code-snippets" 1L, 47B written |]],
			})

			feed("oasdf")
			exec_lua("ls.expand()")

			screen:expect({
				grid = [[
			{"snip": {"prefix": "asdf", "body": ["qwer"]}}    |
			qwer^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
		end
	)

	it("lua-loader refreshes snippets when dependency is written.", function()
		ls_helpers.scratch_mkdir("snippets")

		exec_lua(([[
			require("luasnip.loaders.from_lua").lazy_load({paths="%s"})
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))

		-- this file will provide the body of the snippet.
		ls_helpers.scratch_edit("util/a_string.lua")
		feed([[ireturn "qwer"]])
		feed("<Esc>:w<Cr>")
		exec_lua("vim.wait(100, function() end)")

		ls_helpers.scratch_edit("snippets/all.lua")
		-- extract into variable, so the path does no show up in screen-tests.
		exec_lua(
			([[dependency_file = "%s"]]):format(
				ls_helpers.scratchdir_path .. "/util/a_string.lua"
			)
		)
		feed(
			[[ireturn { ls.parser.parse_snippet("asdf", ls_tracked_dofile(dependency_file)) }]]
		)

		feed("<Esc>:w<Cr>")
		exec_lua("vim.wait(100, function() end)")

		feed("oasdf")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			return { ls.parser.parse_snippet("asdf", ls_tracke|
			d_dofile(dependency_file)) }                      |
			qwer^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		ls_helpers.scratch_edit("util/a_string.lua")
		feed([[<Esc>$bcezxcv]])
		feed("<Esc>:w<Cr>")
		feed("oasdf")

		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			return "zxcv"                                     |
			zxcv^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it(
		"snipmate-loader handles transitive extends, and updates it when changed.",
		function()
			-- setup filetypes A B C D, where A extends B, and C extends D, but B (initially) does not extend C.
			-- If we add this extends, snippets from D should be available in A.
			-- I think if this works, all the "simpler" cases should also work fine. Add more tests if they don't.

			ls_helpers.scratch_mkdir("snippets")
			exec_lua(([[
			require("luasnip.loaders.from_snipmate").lazy_load({paths="%s"})
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))

			ls_helpers.scratch_edit("snippets/A.snippets")
			feed([[iextends B<Esc>:w<Cr>]])
			ls_helpers.scratch_edit("snippets/C.snippets")
			feed([[iextends D<Esc>:w<Cr>]])
			ls_helpers.scratch_edit("snippets/D.snippets")
			feed([[isnippet DDDD<Cr>    dddd<Esc>:w<Cr>]])

			ls_helpers.scratch_edit("snippets/B.snippets")
			feed([[iextends C<Esc>:w<Cr>]])

			exec_lua("vim.wait(100, function() end)")

			exec("set ft=A")
			feed("oDDDD")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
			extends C                                         |
			dddd^                                              |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})

			-- make sure we know that A receives snippets from 4 files,
			-- A/B/C/D.snippets.
			-- This data is used in the edit_snippet_files-dialog, and this check is
			-- to somewhat ensure it behaves consistently (can't test it directly,
			-- unfortunately, I guess since the test-instance waits for input before
			-- proceeding, but as soon as we give it, we can't check the options :( )
			-- Anyway, this works too, for now.
			assert.are.same(
				4,
				exec_lua(
					[[return #require("luasnip.util.table").set_to_list(require("luasnip.loaders.data").snipmate_ft_paths["A"]) ]]
				)
			)
		end
	)

	it(
		"Clearing before a lazy collection is loaded will prevent it from loading.",
		function()
			exec_lua(([[
			require("luasnip.loaders.from_snipmate").load({lazy_paths="%s"})
		]]):format(ls_helpers.scratchdir_path .. "/snippets"))
			exec_lua("ls.cleanup()")

			ls_helpers.scratch_edit("snippets/all.snippets")
			feed([[isnippet DDDD<Cr>    dddd<Esc>:w<Cr>]])
			-- make sure snippets are not loaded because of cleanup, and not
			-- because we don't give the test-instance time to load them :D
			exec_lua("vim.wait(100, function() end)")

			feed("oDDDD")
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
			snippet DDDD                                      |
			    dddd                                          |
			DDDD^                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
		end
	)
end)
