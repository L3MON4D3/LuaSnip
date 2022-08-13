local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("snippetProxy", function()
	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()
		exec_lua("noop = function() end")
	end)

	local no_inst_on_access_test = function(key)
		it("does not instantiate on accessing " .. key, function()
			assert.is_true(
				exec_lua(
					[[local snip = sp("asd", "$1 asdf $2") noop(snip]]
						.. key
						.. [[) return rawget(snip, "_snippet") == nil]]
				)
			)
		end)
	end

	for _, v in ipairs({
		".trigger",
		".hidden",
		".docstring",
		".wordTrig",
		".regTrig",
		".dscr",
		".name",
		".callbacks",
		".condition",
		".show_condition",
		".stored",
		".priority",
		':matches("asd")',
		":get_docstring()",
	}) do
		no_inst_on_access_test(v)
	end

	it("matches correctly", function()
		assert.is_true(
			exec_lua([[return sp("asdf", "$1 asdf $2"):matches("asd") == nil]])
		)
		assert.is_true(
			exec_lua([[return sp("asdf", "$1 asdf $2"):matches("asdf") ~= nil]])
		)
	end)

	it("expands correctly", function()
		local screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})

		exec_lua([[ls.snip_expand(sp("", "$1 asdf $2"))]])

		screen:expect({
			grid = [[
			^ asdf                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	-- one integration test.
	it("works for triggered expansion", function()
		local screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})

		exec_lua([[ls.add_snippets("", { sp("trig", "$1 triggered! $2")})]])

		exec_lua("ls.expand()")
		-- make sure the snippet wasn't instantiated.
		assert.is_true(
			exec_lua(
				[[return rawget(ls.get_snippets("")[1], "_snippet") == nil]]
			)
		)

		feed("itrig")
		exec_lua("ls.expand()")
		-- snippet should be expanded now.
		screen:expect({
			grid = [[
			^ triggered!                                       |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
