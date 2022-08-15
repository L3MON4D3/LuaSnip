local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")
local assert = require("luassert")

local loaders = {
	["vscode(rtp)"] = function()
		exec(
			"set rtp+="
				.. os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/vscode-snippets"
		)
		exec_lua('require("luasnip.loaders.from_vscode").load()')
	end,
	["vscode(path)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_vscode").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
			)
		)
	end,
	["vscode(lazy)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_vscode").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
			)
		)
	end,

	["snipmate(rtp)"] = function()
		exec(
			"set rtp+="
				.. os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/snipmate-snippets"
		)
		exec_lua('require("luasnip.loaders.from_snipmate").load()')
	end,
	["snipmate(path)"] = function(dir)
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/"
					.. dir
			)
		)
	end,
	["snipmate(lazy)"] = function(dir)
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/"
					.. dir
			)
		)
	end,

	["lua(rtp)"] = function()
		exec(
			"set rtp+="
				.. os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/lua-snippets"
		)
		exec_lua('require("luasnip.loaders.from_lua").load()')
	end,
	["lua(path)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets"
			)
		)
	end,
	["lua(lazy)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets"
			)
		)
	end,
}

local function for_all_loaders(message, fn)
	for name, load in pairs(loaders) do
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
		ls_helpers.session_setup_luasnip()

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
		screen:detach()
	end)

	local function reload_test(message, load_fn, snippet_file, edit_keys)
		it(message, function()
			load_fn()

			-- check unmodified.
			feed("iall1")
			exec_lua("ls.expand()")

			screen:expect{grid=[[
				expands? jumps? ^  !                               |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]]}

			-- edit snippet-file to ensure hot-reload works.
			exec(([[
				edit %s
			]]):format(os.getenv("LUASNIP_SOURCE") .. snippet_file))

			-- edit snippet-file, and check for reload.
			feed(edit_keys)

			exec_lua("ls.expand()")
			screen:expect{grid=[[
				replaces? jumps? ^  !                              |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]]}

			-- undo changes to snippet-file.
			feed("<Esc><C-I>u:w<Cr>")
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
		loaders["snipmate(lazy)"]("snippets")
		loaders["vscode(lazy)"]()
		loaders["lua(lazy)"]()
		-- triggers actual load for `lazy_load()`s'
		exec("set ft=lua")
		-- wait a bit for async-operations to finish
		exec('call wait(200, "0")')
		-- one snippet from snipmate, one from vscode.
		assert.are.same(3, exec_lua('return #ls.get_snippets("lua")'))
	end)

	it("Can lazy-load from multiple snipmate-collections.", function()
		loaders["snipmate(lazy)"]("snippets")
		loaders["snipmate(lazy)"]("snippets1")
		exec("set ft=lua")
		-- triggers actual load for `lazy_load()`s'
		-- wait a bit for async-operations to finish
		exec('call wait(200, "0")')
		-- one snippet from snippets, another from snippets1.
		assert.are.same(2, exec_lua('return #ls.get_snippets("lua")'))
	end)

	it("Can load with extends (snipmate)", function()
		loaders["snipmate(lazy)"]("snippets")
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
		loaders["vscode(rtp)"]()
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
		loaders["snipmate(rtp)"]()
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

	reload_test(
		"snipmate-reload works",
		loaders["snipmate(rtp)"],
		"/tests/data/snipmate-snippets/snippets/all.snippets",
		"<Esc>2jwcereplaces<Esc>:w<Cr><C-O>ccall1" )

	reload_test(
		"vscode-reload works",
		loaders["vscode(rtp)"],
		"/tests/data/vscode-snippets/snippets/all.json",
		"<Esc>4jwlcereplaces<Esc>:w<Cr><C-O>ccall1" )

	reload_test(
		"lua-reload works",
		loaders["lua(rtp)"],
		"/tests/data/lua-snippets/luasnippets/all.lua",
		"<Esc>jfecereplaces<Esc>:w<Cr><C-O>ccall1" )

end)
