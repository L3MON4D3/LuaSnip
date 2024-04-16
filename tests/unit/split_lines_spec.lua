local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec

describe("split_lines", function()
	local function check(test_name, filestring, lines)
		-- escape control-characters.
		filestring = filestring:gsub("\r", "\\r")
		filestring = filestring:gsub("\n", "\\n")
		it(test_name, function()
			assert.are.same(
				lines,
				exec_lua(
					'return require("luasnip.loaders.util").split_lines("'
						.. filestring
						.. '")'
				)
			)
		end)
	end

	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	-- LUASNIP_SOURCE is set in makefile (or before that, even).
	exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))
	exec_lua('vim.env.MYVIMRC = "/.vimrc"')

	check("works for DOS-files", "aaa\r\nbbb\r\nccc", { "aaa", "bbb", "ccc" })
	check(
		"works for DOS-files with empty last line",
		"aaa\r\nbbb\r\nccc\r\n",
		{ "aaa", "bbb", "ccc", "" }
	)
	check(
		"works for DOS-files with multiple empty lines",
		"aaa\r\n\r\n\r\nccc",
		{ "aaa", "", "", "ccc" }
	)

	check("works for unix-files", "aaa\nbbb\nccc\n", { "aaa", "bbb", "ccc" })
	check(
		"works for unix-files with empty last line",
		"aaa\nbbb\nccc\n\n",
		{ "aaa", "bbb", "ccc", "" }
	)
	check(
		"works for unix-files with multiple empty lines",
		"aaa\n\n\nccc\n",
		{ "aaa", "", "", "ccc" }
	)

	check("works for mac-files", "aaa\rbbb\rccc\r", { "aaa", "bbb", "ccc" })
	check(
		"works for mac-files with empty last line",
		"aaa\rbbb\rccc\r\r",
		{ "aaa", "bbb", "ccc", "" }
	)
	check(
		"works for mac-files with multiple empty lines",
		"aaa\r\r\rccc\r",
		{ "aaa", "", "", "ccc" }
	)
end)
