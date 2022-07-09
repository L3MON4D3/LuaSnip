local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua

describe("luasnip.extra.otf", function()
	local function check(test_name, input, output)
		it(test_name, function()
			assert.are.same(
				output,
				exec_lua(
					[=[
					local _, parts, _ = require("luasnip.extras.otf")._snippet_chunks(..., 1)
                                        return parts
                                        ]=],
					input
				)
			)
		end)
	end

	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	check("Only text", "one", { { "TXT", "one" } })
	check("Text and inputs", "local $val = require'module'.$color", {
		{ "TXT", "local " },
		{ "INP", "val" },
		{ "TXT", " = require'module'." },
		{ "INP", "color" },
	})

	check(
		"Multiline text with escapes",
		"$something is more important than $$\nbut you can have both --$someone",
		{
			{ "INP", "something" },
			{ "TXT", " is more important than " },
			{ "TXT", "$" },
			{ "EOL" },
			{ "TXT", "but you can have both --" },
			{ "INP", "someone" },
		}
	)

	check(
		"Empty placeholder",
		"asdf $ asdf",
		{ { "TXT", "asdf " }, { "INP", "" }, { "TXT", " asdf" } }
	)

	check(
		"End with empty placeholder",
		"asdf $",
		{ { "TXT", "asdf " }, { "INP", "" } }
	)
end)
