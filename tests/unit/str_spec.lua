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
