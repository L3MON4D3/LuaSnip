local ls = require'luasnip'
-- some shorthands...
local s = ls.s
local sn = ls.sn
local t = ls.t
local i = ls.i
local f = ls.f
local c = ls.c

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
	}),
	s("class", {
		-- Choice: Switch between two different Nodes, first parameter is its position, second a list of nodes.
		c(1, {
			t({"public "}),
			t({"private "})
		}),
		t({"class "}),
		i(2),
		t({" "}),
		c(3, {
			t({"{"}),
			-- sn: Nested Snippet. Instead of a trigger, it has a position, just like insert-nodes.
			-- Inside Choices, Nodes don't need a position as the choice node is the one being jumped to.
			sn(nil, {
				t({"extends "}),
				i(0),
				t({" {"})
			}),
			sn(nil, {
				t({"implements "}),
				i(0),
				t({" {"})
			})
		}),
		t({"","\t"}),
		i(0),
		t({"", "}"})
	}),
}
