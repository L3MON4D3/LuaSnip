local helpers = require("test.functional.helpers")(after_each)

---@param params { msg: string, fmt: string, args: string, expected: string, opts: string, prolouge: string}
local works = function(params)
	it(params.msg, function()
		-- normally `exec_lua` accepts a table which is passed to the code as `...`, but it
		-- fails if number- and string-keys are mixed ({1,2} works fine, {1, b=2} fails).
		-- So we limit ourselves to just passing strings, which are then turned into tables
		-- while load()ing the function.
		local result = helpers.exec_lua(string.format(
			[[
						local args = %s
						local mock_args = {}

						local fake_metatable = {
							__tostring = function(self)
								return self.value
							end,
							get_jump_index = function(self) return nil end
						}
						fake_metatable.__index = fake_metatable

						local fake_node = function(value)
							return setmetatable({value = value}, fake_metatable)
						end
						for key, arg in pairs(args) do
							mock_args[key] = fake_node(arg)
						end
						local result = require("luasnip.extras.fmt").interpolate("%s", mock_args, %s)

						local str_result = ""
						for _, value in pairs(result) do
							str_result = str_result .. tostring(value)
						end
						return str_result
						]],
			params.args,
			params.fmt,
			params.opts
		))
		assert.are.same(params.expected, result)
	end)
end

local fails = function(msg, fmt, args, opts)
	it(msg, function()
		assert.has_error(function()
			helpers.exec_lua(
				string.format(
					'return require("luasnip.extras.fmt").interpolate("%s", %s, %s)',
					fmt,
					args,
					opts
				)
			)
		end)
	end)
end

describe("fmt.interpolate", function()
	-- apparently clear() needs to run before anything else...
	helpers.clear()
	-- set in makefile.
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	works({
		msg = "expands with no numbers",
		fmt = "a{}b{}c{}d",
		args = "{ 4, 5, 6 }",
		expected = "a4b5c6d",
	})

	works({
		msg = "expands with explicit numbers",
		fmt = "a{2}b{1}c{3}d",
		args = "{ 4, 5, 6 }",
		expected = "a5b4c6d",
	})

	works({
		msg = "expands with mixed numbering",
		fmt = "a{}b{3}c{}d{2}e",
		args = "{ 1, 2, 3, 4 }",
		expected = "a1b3c4d2e",
	})

	works({
		msg = "expands named placeholders",
		fmt = "a{A}b{B}c{C}d",
		args = "{ A = 1, B = 2, C = 3 }",
		expected = "a1b2c3d",
	})

	works({
		msg = "expands all mixed",
		fmt = "a {A} b {} c {3} d {} e {B} f {A} g {2} h",
		args = "{ 1, 2, 3, 4, A = 10, B = 20 }",
		expected = "a 10 b 1 c 3 d 4 e 20 f 10 g 2 h",
	})

	works({
		msg = "current index changed by numbered nodes",
		fmt = "{} {} {1} {} {}",
		args = "{ 1, 2, 3 }",
		expected = "1 2 1 2 3",
	})

	works({
		msg = "excludes trailing text",
		fmt = "{}abcd{}",
		args = "{ 1, 2 }",
		expected = "1abcd2",
	})

	works({
		msg = "escapes empty double-braces",
		fmt = "a{{}}b{}c{{}}d{}e",
		args = "{ 2, 4 }",
		expected = "a{}b2c{}d4e",
	})

	works({
		msg = "escapes non-empty double-braces",
		fmt = "a{{d}}b{}c",
		args = "{ 2 }",
		expected = "a{d}b2c",
	})

	works({
		msg = "do not trim placeholders with whitespace",
		fmt = "a{ something}b{}c",
		args = '{ 2, [" something"] = 1 }',
		expected = "a1b2c",
	})

	works({
		msg = "replaces nested escaped braces",
		fmt = "a{{{{}}}}b{}c{{ {{ }}}}d",
		args = "{ 2 }",
		expected = "a{{}}b2c{ { }}d",
	})

	works({
		msg = "replaces umatched escaped braces",
		fmt = "a{{{{b{}c",
		args = "{ 2 }",
		expected = "a{{b2c",
	})

	works({
		msg = "replaces in braces inside escaped braces",
		fmt = "a{{{}}}b{{ {}}}c{{{} }}d{{ {} }}e",
		args = "{ 1, 2, 3, 4 }",
		expected = "a{1}b{ 2}c{3 }d{ 4 }e",
	})

	works({
		msg = "repeats node with default options",
		fmt = "{a}{a}",
		args = "{a = 1}",
		expected = "11",
	})

	fails("fails for unbalanced braces", "a{b", {})

	fails("fails for nested braces", "a{ { } }b", {})

	works({
		msg = "can use different delimiters",
		fmt = "foo() { return <>; };",
		args = "{ 10 }",
		expected = "foo() { return 10; };",
		opts = '{ delimiters = "<>" }',
	})

	local delimiters = { "()", "[]", "<>", "%$", "#@", "?!" }
	for _, delims in ipairs(delimiters) do
		local left, right = delims:sub(1, 1), delims:sub(2, 2)
		describe("can use custom delimiters", function()
			works({
				msg = delims,
				fmt = string.format("{ return %s%s; };", left, right),
				args = "{ 10 }",
				expected = "{ return 10; };",
				opts = string.format('{ delimiters = "%s" }', delims),
			})
		end)
	end

	works({
		msg = "can escape custom delimiters",
		fmt = "foo((x)) { return x + (); };",
		args = "{ 10 }",
		expected = "foo(x) { return x + 10; };",
		opts = '{ delimiters = "()" }',
	})

	works({
		msg = "can use named placeholders with custom delimiters",
		fmt = "foo(x) { return x + [y]; };",
		args = "{ y = 10 }",
		expected = "foo(x) { return x + 10; };",
		opts = '{ delimiters = "[]" }',
	})

	fails("dissallows unused list args", "a {} b {} c", "{ 1, 2, 3 }")

	fails(
		"dissallows unused map args",
		"a {A} b {B} c {} d",
		"{ 1, A = 10, B = 20, C = 30 }"
	)

	works({
		msg = "allows unused with strict=false",
		fmt = "a {A} b {B} c {} d",
		args = "{ 1, 2, A = 10, B = 20, C = 30 }",
		expected = "a 10 b 20 c 1 d",
		opts = "{ strict = false }",
	})
end)
