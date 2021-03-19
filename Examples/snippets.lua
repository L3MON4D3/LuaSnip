local ls = require'luasnip'
-- some shorthands...
local s = ls.s
local t = ls.t
local i = ls.i
local f = ls.f

-- args is a table, where 1 is the text in Placeholder 1, 2 the text in
-- placeholder 2,...
local function copy(args) return args[1] end

ls.snippets = {
	-- trigger is fn.
	s("fn", {
		-- Simple static text.
		t({"function "}),
		-- Placeholder/Insert.
		i(1),
		t({"("}),
		-- Placeholder with initial text.
		i(2, {"int foo"}),
		t({")"}),
		-- Linebreak
		t({" {","\t"}),
		-- function, first parameter is the function, second the Placeholders
		-- whose text it gets as input.
		f(copy, {2}),
		-- Last Placeholder, exit Point of the snippet. EVERY SNIPPET NEEDS Placeholder 0.
		i(0),
		t({"", "}"})
	})
}
