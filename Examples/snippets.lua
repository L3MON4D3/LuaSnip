local ls = require("luasnip")
-- some shorthands...
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local l = require("luasnip.extras").lambda
local rep = require("luasnip.extras").rep
local p = require("luasnip.extras").partial
local m = require("luasnip.extras").match
local n = require("luasnip.extras").nonempty
local dl = require("luasnip.extras").dynamic_lambda
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local types = require("luasnip.util.types")
local conds = require("luasnip.extras.conditions")
local conds_expand = require("luasnip.extras.conditions.expand")

-- If you're reading this file for the first time, best skip to around line 190
-- where the actual snippet-definitions start.

-- Every unspecified option will be set to the default.
ls.setup({
	keep_roots = true,
	link_roots = true,
	link_children = true,

	-- Update more often, :h events for more info.
	update_events = "TextChanged,TextChangedI",
	-- Snippets aren't automatically removed if their text is deleted.
	-- `delete_check_events` determines on which events (:h events) a check for
	-- deleted snippets is performed.
	-- This can be especially useful when `history` is enabled.
	delete_check_events = "TextChanged",
	ext_opts = {
		[types.choiceNode] = {
			active = {
				virt_text = { { "choiceNode", "Comment" } },
			},
		},
	},
	-- treesitter-hl has 100, use something higher (default is 200).
	ext_base_prio = 300,
	-- minimal increase in priority.
	ext_prio_increase = 1,
	enable_autosnippets = true,
	-- mapping for cutting selected text so it's usable as SELECT_DEDENT,
	-- SELECT_RAW or TM_SELECTED_TEXT (mapped via xmap).
	store_selection_keys = "<Tab>",
	-- luasnip uses this function to get the currently active filetype. This
	-- is the (rather uninteresting) default, but it's possible to use
	-- eg. treesitter for getting the current filetype by setting ft_func to
	-- require("luasnip.extras.filetype_functions").from_cursor (requires
	-- `nvim-treesitter/nvim-treesitter`). This allows correctly resolving
	-- the current filetype in eg. a markdown-code block or `vim.cmd()`.
	ft_func = function()
		return vim.split(vim.bo.filetype, ".", true)
	end,
})

-- args is a table, where 1 is the text in Placeholder 1, 2 the text in
-- placeholder 2,...
local function copy(args)
	return args[1]
end

-- 'recursive' dynamic snippet. Expands to some text followed by itself.
local rec_ls
rec_ls = function()
	return sn(
		nil,
		c(1, {
			-- Order is important, sn(...) first would cause infinite loop of expansion.
			t(""),
			sn(nil, { t({ "", "\t\\item " }), i(1), d(2, rec_ls, {}) }),
		})
	)
end

-- complicated function for dynamicNode.
local function jdocsnip(args, _, old_state)
	-- !!! old_state is used to preserve user-input here. DON'T DO IT THAT WAY!
	-- Using a restoreNode instead is much easier.
	-- View this only as an example on how old_state functions.
	local nodes = {
		t({ "/**", " * " }),
		i(1, "A short Description"),
		t({ "", "" }),
	}

	-- These will be merged with the snippet; that way, should the snippet be updated,
	-- some user input eg. text can be referred to in the new snippet.
	local param_nodes = {}

	if old_state then
		nodes[2] = i(1, old_state.descr:get_text())
	end
	param_nodes.descr = nodes[2]

	-- At least one param.
	if string.find(args[2][1], ", ") then
		vim.list_extend(nodes, { t({ " * ", "" }) })
	end

	local insert = 2
	for indx, arg in ipairs(vim.split(args[2][1], ", ", true)) do
		-- Get actual name parameter.
		arg = vim.split(arg, " ", true)[2]
		if arg then
			local inode
			-- if there was some text in this parameter, use it as static_text for this new snippet.
			if old_state and old_state[arg] then
				inode = i(insert, old_state["arg" .. arg]:get_text())
			else
				inode = i(insert)
			end
			vim.list_extend(
				nodes,
				{ t({ " * @param " .. arg .. " " }), inode, t({ "", "" }) }
			)
			param_nodes["arg" .. arg] = inode

			insert = insert + 1
		end
	end

	if args[1][1] ~= "void" then
		local inode
		if old_state and old_state.ret then
			inode = i(insert, old_state.ret:get_text())
		else
			inode = i(insert)
		end

		vim.list_extend(
			nodes,
			{ t({ " * ", " * @return " }), inode, t({ "", "" }) }
		)
		param_nodes.ret = inode
		insert = insert + 1
	end

	if vim.tbl_count(args[3]) ~= 1 then
		local exc = string.gsub(args[3][2], " throws ", "")
		local ins
		if old_state and old_state.ex then
			ins = i(insert, old_state.ex:get_text())
		else
			ins = i(insert)
		end
		vim.list_extend(
			nodes,
			{ t({ " * ", " * @throws " .. exc .. " " }), ins, t({ "", "" }) }
		)
		param_nodes.ex = ins
		insert = insert + 1
	end

	vim.list_extend(nodes, { t({ " */" }) })

	local snip = sn(nil, nodes)
	-- Error on attempting overwrite.
	snip.old_state = param_nodes
	return snip
end

-- Make sure to not pass an invalid command, as io.popen() may write over nvim-text.
local function bash(_, _, command)
	local file = io.popen(command, "r")
	local res = {}
	for line in file:lines() do
		table.insert(res, line)
	end
	return res
end

-- Returns a snippet_node wrapped around an insertNode whose initial
-- text value is set to the current date in the desired format.
local date_input = function(args, snip, old_state, fmt)
	local fmt = fmt or "%Y-%m-%d"
	return sn(nil, i(1, os.date(fmt)))
end

-- snippets are added via ls.add_snippets(filetype, snippets[, opts]), where
-- opts may specify the `type` of the snippets ("snippets" or "autosnippets",
-- for snippets that should expand directly after the trigger is typed).
--
-- opts can also specify a key. By passing an unique key to each add_snippets, it's possible to reload snippets by
-- re-`:luafile`ing the file in which they are defined (eg. this one).
ls.add_snippets("all", {
	-- trigger is `fn`, second argument to snippet-constructor are the nodes to insert into the buffer on expansion.
	s("fn", {
		-- Simple static text.
		t("//Parameters: "),
		-- function, first parameter is the function, second the Placeholders
		-- whose text it gets as input.
		f(copy, 2),
		t({ "", "function " }),
		-- Placeholder/Insert.
		i(1),
		t("("),
		-- Placeholder with initial text.
		i(2, "int foo"),
		-- Linebreak
		t({ ") {", "\t" }),
		-- Last Placeholder, exit Point of the snippet.
		i(0),
		t({ "", "}" }),
	}),
	s("class", {
		-- Choice: Switch between two different Nodes, first parameter is its position, second a list of nodes.
		c(1, {
			t("public "),
			t("private "),
		}),
		t("class "),
		i(2),
		t(" "),
		c(3, {
			t("{"),
			-- sn: Nested Snippet. Instead of a trigger, it has a position, just like insertNodes. !!! These don't expect a 0-node!!!!
			-- Inside Choices, Nodes don't need a position as the choice node is the one being jumped to.
			sn(nil, {
				t("extends "),
				-- restoreNode: stores and restores nodes.
				-- pass position, store-key and nodes.
				r(1, "other_class", i(1)),
				t(" {"),
			}),
			sn(nil, {
				t("implements "),
				-- no need to define the nodes for a given key a second time.
				r(1, "other_class"),
				t(" {"),
			}),
		}),
		t({ "", "\t" }),
		i(0),
		t({ "", "}" }),
	}),
	-- Alternative printf-like notation for defining snippets. It uses format
	-- string with placeholders similar to the ones used with Python's .format().
	s(
		"fmt1",
		fmt("To {title} {} {}.", {
			i(2, "Name"),
			i(3, "Surname"),
			title = c(1, { t("Mr."), t("Ms.") }),
		})
	),
	-- To escape delimiters use double them, e.g. `{}` -> `{{}}`.
	-- Multi-line format strings by default have empty first/last line removed.
	-- Indent common to all lines is also removed. Use the third `opts` argument
	-- to control this behaviour.
	s(
		"fmt2",
		fmt(
			[[
		foo({1}, {3}) {{
			return {2} * {4}
		}}
		]],
			{
				i(1, "x"),
				rep(1),
				i(2, "y"),
				rep(2),
			}
		)
	),
	-- Empty placeholders are numbered automatically starting from 1 or the last
	-- value of a numbered placeholder. Named placeholders do not affect numbering.
	s(
		"fmt3",
		fmt("{} {a} {} {1} {}", {
			t("1"),
			t("2"),
			a = t("A"),
		})
	),
	-- The delimiters can be changed from the default `{}` to something else.
	s("fmt4", fmt("foo() { return []; }", i(1, "x"), { delimiters = "[]" })),
	-- `fmta` is a convenient wrapper that uses `<>` instead of `{}`.
	s("fmt5", fmta("foo() { return <>; }", i(1, "x"))),
	-- By default all args must be used. Use strict=false to disable the check
	s(
		"fmt6",
		fmt("use {} only", { t("this"), t("not this") }, { strict = false })
	),
	-- Use a dynamicNode to interpolate the output of a
	-- function (see date_input above) into the initial
	-- value of an insertNode.
	s("novel", {
		t("It was a dark and stormy night on "),
		d(1, date_input, {}, { user_args = { "%A, %B %d of %Y" } }),
		t(" and the clocks were striking thirteen."),
	}),
	-- Parsing snippets: First parameter: Snippet-Trigger, Second: Snippet body.
	-- Placeholders are parsed into choices with 1. the placeholder text(as a snippet) and 2. an empty string.
	-- This means they are not SELECTed like in other editors/Snippet engines.
	ls.parser.parse_snippet(
		"lspsyn",
		"Wow! This ${1:Stuff} really ${2:works. ${3:Well, a bit.}}"
	),

	-- When wordTrig is set to false, snippets may also expand inside other words.
	ls.parser.parse_snippet(
		{ trig = "te", wordTrig = false },
		"${1:cond} ? ${2:true} : ${3:false}"
	),

	-- When regTrig is set, trig is treated like a pattern, this snippet will expand after any number.
	ls.parser.parse_snippet({ trig = "%d", regTrig = true }, "A Number!!"),
	-- Using the condition, it's possible to allow expansion only in specific cases.
	s("cond", {
		t("will only expand in c-style comments"),
	}, {
		condition = function(line_to_cursor, matched_trigger, captures)
			-- optional whitespace followed by //
			return line_to_cursor:match("%s*//")
		end,
	}),
	-- there's some built-in conditions in "luasnip.extras.conditions.expand" and "luasnip.extras.conditions.show".
	s("cond2", {
		t("will only expand at the beginning of the line"),
	}, {
		condition = conds_expand.line_begin,
	}),
	s("cond3", {
		t("will only expand at the end of the line"),
	}, {
		condition = conds_expand.line_end,
	}),
	-- on conditions some logic operators are defined
	s("cond4", {
		t("will only expand at the end and the start of the line"),
	}, {
		-- last function is just an example how to make own function objects and apply operators on them
		condition = conds_expand.line_end
			+ conds_expand.line_begin
				* conds.make_condition(function()
					return true
				end),
	}),
	-- The last entry of args passed to the user-function is the surrounding snippet.
	s(
		{ trig = "a%d", regTrig = true },
		f(function(_, snip)
			return "Triggered with " .. snip.trigger .. "."
		end, {})
	),
	-- It's possible to use capture-groups inside regex-triggers.
	s(
		{ trig = "b(%d)", regTrig = true },
		f(function(_, snip)
			return "Captured Text: " .. snip.captures[1] .. "."
		end, {})
	),
	s({ trig = "c(%d+)", regTrig = true }, {
		t("will only expand for even numbers"),
	}, {
		condition = function(line_to_cursor, matched_trigger, captures)
			return tonumber(captures[1]) % 2 == 0
		end,
	}),
	-- Use a function to execute any shell command and print its text.
	s("bash", f(bash, {}, { user_args = { "ls" } })),
	-- Short version for applying String transformations using function nodes.
	s("transform", {
		i(1, "initial text"),
		t({ "", "" }),
		-- lambda nodes accept an l._1,2,3,4,5, which in turn accept any string transformations.
		-- This list will be applied in order to the first node given in the second argument.
		l(l._1:match("[^i]*$"):gsub("i", "o"):gsub(" ", "_"):upper(), 1),
	}),

	s("transform2", {
		i(1, "initial text"),
		t("::"),
		i(2, "replacement for e"),
		t({ "", "" }),
		-- Lambdas can also apply transforms USING the text of other nodes:
		l(l._1:gsub("e", l._2), { 1, 2 }),
	}),
	s({ trig = "trafo(%d+)", regTrig = true }, {
		-- env-variables and captures can also be used:
		l(l.CAPTURE1:gsub("1", l.TM_FILENAME), {}),
	}),
	-- Set store_selection_keys = "<Tab>" (for example) in your
	-- luasnip.config.setup() call to populate
	-- TM_SELECTED_TEXT/SELECT_RAW/SELECT_DEDENT.
	-- In this case: select a URL, hit Tab, then expand this snippet.
	s("link_url", {
		t('<a href="'),
		f(function(_, snip)
			-- TM_SELECTED_TEXT is a table to account for multiline-selections.
			-- In this case only the first line is inserted.
			return snip.env.TM_SELECTED_TEXT[1] or {}
		end, {}),
		t('">'),
		i(1),
		t("</a>"),
		i(0),
	}),
	-- Shorthand for repeating the text in a given node.
	s("repeat", { i(1, "text"), t({ "", "" }), rep(1) }),
	-- Directly insert the ouput from a function evaluated at runtime.
	s("part", p(os.date, "%Y")),
	-- use matchNodes (`m(argnode, condition, then, else)`) to insert text
	-- based on a pattern/function/lambda-evaluation.
	-- It's basically a shortcut for simple functionNodes:
	s("mat", {
		i(1, { "sample_text" }),
		t(": "),
		m(1, "%d", "contains a number", "no number :("),
	}),
	-- The `then`-text defaults to the first capture group/the entire
	-- match if there are none.
	s("mat2", {
		i(1, { "sample_text" }),
		t(": "),
		m(1, "[abc][abc][abc]"),
	}),
	-- It is even possible to apply gsubs' or other transformations
	-- before matching.
	s("mat3", {
		i(1, { "sample_text" }),
		t(": "),
		m(
			1,
			l._1:gsub("[123]", ""):match("%d"),
			"contains a number that isn't 1, 2 or 3!"
		),
	}),
	-- `match` also accepts a function in place of the condition, which in
	-- turn accepts the usual functionNode-args.
	-- The condition is considered true if the function returns any
	-- non-nil/false-value.
	-- If that value is a string, it is used as the `if`-text if no if is explicitly given.
	s("mat4", {
		i(1, { "sample_text" }),
		t(": "),
		m(1, function(args)
			-- args is a table of multiline-strings (as usual).
			return (#args[1][1] % 2 == 0 and args[1]) or nil
		end),
	}),
	-- The nonempty-node inserts text depending on whether the arg-node is
	-- empty.
	s("nempty", {
		i(1, "sample_text"),
		n(1, "i(1) is not empty!"),
	}),
	-- dynamic lambdas work exactly like regular lambdas, except that they
	-- don't return a textNode, but a dynamicNode containing one insertNode.
	-- This makes it easier to dynamically set preset-text for insertNodes.
	s("dl1", {
		i(1, "sample_text"),
		t({ ":", "" }),
		dl(2, l._1, 1),
	}),
	-- Obviously, it's also possible to apply transformations, just like lambdas.
	s("dl2", {
		i(1, "sample_text"),
		i(2, "sample_text_2"),
		t({ "", "" }),
		dl(3, l._1:gsub("\n", " linebreak ") .. l._2, { 1, 2 }),
	}),
}, {
	key = "all",
})

ls.add_snippets("java", {
	-- Very long example for a java class.
	s("fn", {
		d(6, jdocsnip, { 2, 4, 5 }),
		t({ "", "" }),
		c(1, {
			t("public "),
			t("private "),
		}),
		c(2, {
			t("void"),
			t("String"),
			t("char"),
			t("int"),
			t("double"),
			t("boolean"),
			i(nil, ""),
		}),
		t(" "),
		i(3, "myFunc"),
		t("("),
		i(4),
		t(")"),
		c(5, {
			t(""),
			sn(nil, {
				t({ "", " throws " }),
				i(1),
			}),
		}),
		t({ " {", "\t" }),
		i(0),
		t({ "", "}" }),
	}),
}, {
	key = "java",
})

ls.add_snippets("tex", {
	-- rec_ls is self-referencing. That makes this snippet 'infinite' eg. have as many
	-- \item as necessary by utilizing a choiceNode.
	s("ls", {
		t({ "\\begin{itemize}", "\t\\item " }),
		i(1),
		d(2, rec_ls, {}),
		t({ "", "\\end{itemize}" }),
	}),
}, {
	key = "tex",
})

-- set type to "autosnippets" for adding autotriggered snippets.
ls.add_snippets("all", {
	s("autotrigger", {
		t("autosnippet"),
	}),
}, {
	type = "autosnippets",
	key = "all_auto",
})

-- in a lua file: search lua-, then c-, then all-snippets.
ls.filetype_extend("lua", { "c" })
-- in a cpp file: search c-snippets, then all-snippets only (no cpp-snippets!!).
ls.filetype_set("cpp", { "c" })

-- Beside defining your own snippets you can also load snippets from "vscode-like" packages
-- that expose snippets in json files, for example <https://github.com/rafamadriz/friendly-snippets>.

require("luasnip.loaders.from_vscode").load({ include = { "python" } }) -- Load only python snippets

-- The directories will have to be structured like eg. <https://github.com/rafamadriz/friendly-snippets> (include
-- a similar `package.json`)
require("luasnip.loaders.from_vscode").load({ paths = { "./my-snippets" } }) -- Load snippets from my-snippets folder

-- You can also use lazy loading so snippets are loaded on-demand, not all at once (may interfere with lazy-loading luasnip itself).
require("luasnip.loaders.from_vscode").lazy_load() -- You can pass { paths = "./my-snippets/"} as well

-- You can also use snippets in snipmate format, for example <https://github.com/honza/vim-snippets>.
-- The usage is similar to vscode.

-- One peculiarity of honza/vim-snippets is that the file containing global
-- snippets is _.snippets, so we need to tell luasnip that the filetype "_"
-- contains global snippets:
ls.filetype_extend("all", { "_" })

require("luasnip.loaders.from_snipmate").load({ include = { "c" } }) -- Load only snippets for c.

-- Load snippets from my-snippets folder
-- The "." refers to the directory where of your `$MYVIMRC` (you can print it
-- out with `:lua print(vim.env.MYVIMRC)`.
-- NOTE: It's not always set! It isn't set for example if you call neovim with
-- the `-u` argument like this: `nvim -u yeet.txt`.
require("luasnip.loaders.from_snipmate").load({ path = { "./my-snippets" } })
-- If path is not specified, luasnip will look for the `snippets` directory in rtp (for custom-snippet probably
-- `~/.config/nvim/snippets`).

require("luasnip.loaders.from_snipmate").lazy_load() -- Lazy loading

-- see DOC.md/LUA SNIPPETS LOADER for some details.
require("luasnip.loaders.from_lua").load({ include = { "c" } })
require("luasnip.loaders.from_lua").lazy_load({ include = { "all", "cpp" } })
