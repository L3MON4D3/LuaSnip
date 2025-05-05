local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec

local works = function(msg, string, left, right, expected)
	it(msg, function()
		-- normally `exec_lua` accepts a table which is passed to the code as `...`, but it
		-- fails if number- and string-keys are mixed ({1,2} works fine, {1, b=2} fails).
		-- So we limit ourselves to just passing strings, which are then turned into tables
		-- while load()ing the function.
		local result = exec_lua(string.format(
			[[
					local res = {}
					for from, to in require("luasnip.util.str").unescaped_pairs("%s", "%s", "%s") do
						table.insert(res, {from, to})
					end
					return res
				]],
			string,
			left,
			right
		))
		assert.are.same(expected, result)
	end)
end

describe("str.unescaped_pairs", function()
	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	ls_helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	-- double \, since it is turned into a string twice.
	works(
		"simple parenthesis",
		"a (bb) c (dd\\\\)) e",
		"(",
		")",
		{ { 3, 6 }, { 10, 15 } }
	)
	works(
		"both parens escaped",
		"a \\\\(bb\\\\) c (dd\\\\)) e",
		"(",
		")",
		{ { 12, 17 } }
	)
	works("left=right", "``````", "`", "`", { { 1, 2 }, { 3, 4 }, { 5, 6 } })
	works(
		"random escaped characters",
		"`a`e`\\\\``i`",
		"`",
		"`",
		{ { 1, 3 }, { 5, 8 } }
	)
	works(
		"double escaped = literal `\\`",
		"`a`e`\\\\\\\\``i`",
		"`",
		"`",
		{ { 1, 3 }, { 5, 8 }, { 9, 11 } }
	)
end)

describe("str.dedent", function()
	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))
	local function get_dedent_result(input_string)
		local result = exec_lua(
			string.format(
				[[return require("luasnip.util.str").dedent("%s")]],
				input_string
			)
		)
		return result
	end

	it("spaces at beginnig", function()
		local input_table = {
			"  line1",
			"  ",
			"    line3",
			"      line4",
		}
		local input_string = table.concat(input_table, [[\n]])
		local expect_table = {
			"line1",
			"",
			"  line3",
			"    line4",
		}
		local expected = table.concat(expect_table, "\n")

		local result = get_dedent_result(input_string)

		assert.are.same(expected, result)
	end)
	it("tabs at beginnig", function()
		local input_table = {
			[[\t\tline1]],
			[[\t\t]],
			[[\t\t\tline3]],
			[[\t\t\t\tline4]],
		}
		local input_string = table.concat(input_table, [[\n]])
		local expect_table = {
			"line1",
			"",
			"\tline3",
			"\t\tline4",
		}
		local expected = table.concat(expect_table, "\n")

		local result = get_dedent_result(input_string)

		assert.are.same(expected, result)
	end)
	it("tabs & spaces at beginnig", function()
		local input_table = {
			[[\t\t line1]],
			[[\t\t ]],
			[[\t\t \t  line3]],
			[[\t\t \t\t  line4]],
		}
		local input_string = table.concat(input_table, [[\n]])
		local expect_table = {
			"line1",
			"",
			"\t  line3",
			"\t\t  line4",
		}
		local expected = table.concat(expect_table, "\n")

		local result = get_dedent_result(input_string)

		assert.are.same(expected, result)
	end)
end)

describe("str.convert_indent", function()
	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))
	local function get_convert_indent_result(input_string, indent_string)
		local result = exec_lua(
			string.format(
				[[return require("luasnip.util.str").convert_indent("%s", "%s")]],
				input_string,
				indent_string
			)
		)
		return result
	end

	it("two spaces to tab", function()
		local input_table = {
			"line1: no indent",
			"",
			"  line3: 1 indent",
			"    line4: 2 indent",
		}
		local input_string = table.concat(input_table, [[\n]])
		local indent_string = "  "
		local expect_table = {
			"line1: no indent",
			"",
			"\tline3: 1 indent",
			"\t\tline4: 2 indent",
		}
		local expected = table.concat(expect_table, "\n")

		local result = get_convert_indent_result(input_string, indent_string)

		assert.are.same(expected, result)
	end)
	it([[literal \t to tab]], function()
		local input_table = {
			"line1: no indent",
			"",
			[[\\tline3: 1 indent]],
			[[\\t\\tline4: 2 indent]],
		}
		local input_string = table.concat(input_table, [[\n]])
		local indent_string = [[\\t]]
		local expect_table = {
			"line1: no indent",
			"",
			"\tline3: 1 indent",
			"\t\tline4: 2 indent",
		}
		local expected = table.concat(expect_table, "\n")

		local result = get_convert_indent_result(input_string, indent_string)

		assert.are.same(expected, result)
	end)
end)

describe("str.multiline_substr", function()
	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	ls_helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	local function check(dscr, str, from, to, expected)
		it(dscr, function()
			assert.are.same(
				expected,
				exec_lua(
					[[
				local str, from, to = ...
				return require("luasnip.util.str").multiline_substr(str, from, to)
			]],
					str,
					from,
					to
				)
			)
		end)
	end

	check(
		"entire range",
		{ "asdf", "qwer" },
		{ 0, 0 },
		{ 1, 4 },
		{ "asdf", "qwer" }
	)
	check(
		"partial range",
		{ "asdf", "qwer" },
		{ 0, 3 },
		{ 1, 2 },
		{ "f", "qw" }
	)
	check(
		"another partial range",
		{ "asdf", "qwer" },
		{ 1, 2 },
		{ 1, 3 },
		{ "e" }
	)
	check(
		"one last partial range",
		{ "asdf", "qwer", "zxcv" },
		{ 0, 2 },
		{ 2, 4 },
		{ "df", "qwer", "zxcv" }
	)
	check("empty range", { "asdf", "qwer", "zxcv" }, { 0, 2 }, { 0, 2 }, { "" })
end)

describe("str.multiline_to_byte_offset", function()
	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	ls_helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	local function check(dscr, str, multiline_pos, byte_pos)
		it(dscr, function()
			assert.are.same(
				byte_pos,
				exec_lua(
					[[
				local str, multiline_pos = ...
				return require("luasnip.util.str").multiline_to_byte_offset(str, multiline_pos)
			]],
					str,
					multiline_pos
				)
			)
		end)
	end
	local function check_is_nil(dscr, str, multiline_pos, byte_pos)
		it(dscr, function()
			assert(exec_lua(
				[[
				local str, multiline_pos = ...
				return require("luasnip.util.str").multiline_to_byte_offset(str, multiline_pos) == nil
			]],
				str,
				multiline_pos
			))
		end)
	end

	check("single line begin", { "asdf" }, { 0, 0 }, 1)
	check("single line middle", { "asdf" }, { 0, 2 }, 3)
	check("single line end", { "asdf" }, { 0, 3 }, 4)
	check("single line, on \n", { "asdf" }, { 0, 4 }, 5)
	check_is_nil("single line, outside of range", { "asdf" }, { 0, 5 })
	check("multiple lines", { "asdf", "qwer" }, { 1, 0 }, 6)
	check("multiple lines middle", { "asdf", "qwer" }, { 1, 3 }, 9)
	check_is_nil(
		"multiple lines outside of range row",
		{ "asdf", "qwer" },
		{ 2, 0 }
	)
	check("on linebreak", { "asdf", "qwer" }, { 0, 4 }, 5)
	check("on linebreak of last line", { "asdf", "qwer" }, { 1, 4 }, 10)
	check_is_nil("negative row", { "asdf", "qwer" }, { -1, 0 })
	check_is_nil("negative col", { "asdf", "qwer" }, { 0, -2 })
	check("unicode1", { "aa … aa" }, { 0, 6 }, 7)
	check("unicode2", { "aa …a… aa" }, { 0, 6 }, 7)
	check("unicode3", { "aa …a… aa", "aa …a… aa" }, { 1, 6 }, 21)
end)

describe("byte_to_multiline_offset", function()
	-- apparently clear() needs to run before anything else...
	ls_helpers.clear()
	ls_helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	local function check(dscr, str, byte_pos, multiline_pos)
		it(dscr, function()
			assert.are.same(
				multiline_pos,
				exec_lua(
					[[
				local str, byte_pos = ...
				return require("luasnip.util.str").byte_to_multiline_offset(str, byte_pos)
			]],
					str,
					byte_pos
				)
			)
		end)
	end
	local function check_is_nil(dscr, str, byte_pos, multiline_pos)
		it(dscr, function()
			assert(exec_lua(
				[[
				local str, byte_pos = ...
				return require("luasnip.util.str").byte_to_multiline_offset(str, byte_pos) == nil
			]],
				str,
				byte_pos
			))
		end)
	end

	check("single line begin", { "asdf" }, 1, { 0, 0 })
	check("single line middle", { "asdf" }, 3, { 0, 2 })
	check("single line end", { "asdf" }, 4, { 0, 3 })
	check("single line on linebreak", { "asdf" }, 5, { 0, 4 })
	check("multiple lines", { "asdf", "qwer" }, 6, { 1, 0 })
	check("multiple lines middle", { "asdf", "qwer" }, 9, { 1, 3 })
	check("multiple lines middle linebreak", { "asdf", "qwer" }, 10, { 1, 4 })
	check_is_nil("before string", { "asdf", "qwer" }, -1)
	check_is_nil("multiple lines behind string", { "asdf", "qwer" }, 11)
	check("unicode1", { "aa … aa" }, 7, { 0, 6 })
	check("unicode2", { "aa …a… aa" }, 7, { 0, 6 })
	check("unicode3", { "aa …a… aa", "aa …a… aa" }, 21, { 1, 6 })
end)
