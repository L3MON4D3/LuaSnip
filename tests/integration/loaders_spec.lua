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
			-- wait a bit for async-operations to finish
			-- Bad, load (even lazy_load) will be synchronous (soon).
			exec('call wait(200, "0")')
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
end)
