local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("snippets_basic", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		exec([[
			hi Blue ctermfg=Blue guifg=Blue
			hi Green ctermfg=Green guifg=Green
			hi Cyan ctermfg=Cyan guifg=Cyan
			hi Red ctermfg=Red guifg=Red
		]])

		screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue1 },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
			[4] = { foreground = Screen.colors.WebGreen },
			[5] = { foreground = Screen.colors.Blue1 },
			[6] = {
				background = Screen.colors.LightGray,
				foreground = Screen.colors.Blue1,
			},
			[7] = { foreground = Screen.colors.Cyan1 },
			[8] = {
				background = Screen.colors.LightGray,
				foreground = Screen.colors.Cyan1,
			},
			[9] = { foreground = Screen.colors.Red },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("Can apply ext_opts per-node", function()
		local snip = [[
			s("trig", {
				t("Green", {
					node_ext_opts = {
						passive = {hl_group = "Green"}
					}
				}),
				-- so the snippet is active at all.
				i(1, "text", {
					node_ext_opts = {
						passive = {hl_group = "Blue"}
					}
				})
			})
		]]
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			{4:Green}{5:^t}{6:ext}                                         |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			Greentext^                                         |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("Correctly applies active,visited,unvisited", function()
		local snip = [[
			s("trig", {
				-- so the snippet is active at all.
				i(1, "text", {
					node_ext_opts = {
						unvisited = {hl_group = "Blue"},
						visited = {hl_group = "Green"},
						active = {hl_group = "Cyan"}
					}
				}),
				i(2, "text", {
					node_ext_opts = {
						unvisited = {hl_group = "Blue"},
						visited = {hl_group = "Green"},
						active = {hl_group = "Cyan"}
					}
				}),
				i(3, "text", {
					node_ext_opts = {
						unvisited = {hl_group = "Blue"},
						visited = {hl_group = "Green"},
						active = {hl_group = "Cyan"}
					}
				})
			})
		]]
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			{7:^t}{8:ext}{5:texttext}                                      |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			{4:text}{7:^t}{8:ext}{5:text}                                      |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			{4:texttext}{7:^t}{8:ext}                                      |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it("Inheritance", function()
		local snip = [[
			s("trig", {
				-- so the snippet is active at all.
				i(1, "text", {
					node_ext_opts = {
						snippet_passive = {hl_group = "Red"},
						passive = {hl_group = "Blue"},
						visited = {hl_group = "Green"},
						active = {hl_group = "Cyan"}
					}
				}),
				i(2, "text", {
					node_ext_opts = {
						passive = {hl_group = "Blue"},
						visited = {hl_group = "Green"},
						active = {hl_group = "Cyan"}
					}
				}),
			})
		]]
		exec_lua("ls.snip_expand(" .. snip .. ")")
		screen:expect({
			grid = [[
			{7:^t}{8:ext}{5:text}                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			{4:text}{7:^t}{8:ext}                                          |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		exec_lua("ls.jump(1)")
		screen:expect({
			grid = [[
			{9:text}text^                                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
end)
