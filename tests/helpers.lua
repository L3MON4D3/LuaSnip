local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua
local assert = require("luassert")

local M = {}

function M.setup_jsregexp()
	-- append default-path.
	exec_lua(
		('package.cpath = "%s"'):format(os.getenv("JSREGEXP_PATH") .. "/?.so;;")
	)
end

function M.session_setup_luasnip()
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))
	helpers.exec(
		string.format(
			"source %s/plugin/luasnip.vim",
			os.getenv("LUASNIP_SOURCE")
		)
	)

	helpers.exec_lua([[

	-- MYVIMRC might not be set when nvim is loaded like this.
	vim.env.MYVIMRC = "/.vimrc"

	ls = require("luasnip")
	ls.setup({
		store_selection_keys = "<Tab>"
	})

	s = ls.s
	sn = ls.sn
	t = ls.t
	i = ls.i
	f = ls.f
	c = ls.c
	d = ls.d
	isn = require("luasnip.nodes.snippet").ISN
	l = require'luasnip.extras'.lambda
	dl = require'luasnip.extras'.dynamic_lambda
	rep = require'luasnip.extras'.rep
	r = ls.restore_node
	p = require("luasnip.extras").partial
	types = require("luasnip.util.types")
	events = require("luasnip.util.events")
	fmt = require("luasnip.extras.fmt").fmt
	fmta = require("luasnip.extras.fmt").fmta
	parse = ls.parser.parse_snippet
	n = require("luasnip.extras").nonempty
	m = require("luasnip.extras").match
	ai = require("luasnip.nodes.absolute_indexer")
	sp = require("luasnip.nodes.snippetProxy")
	pf = require("luasnip.extras.postfix").postfix
	]])
end

function M.static_docstring_test(snip_str, static, docstring)
	assert.are.same(
		static,
		exec_lua("return " .. snip_str .. ":get_static_text()")
	)
	assert.are.same(
		docstring,
		exec_lua("return " .. snip_str .. ":get_docstring()")
	)
end
function M.lsp_static_test(snip_str, static)
	assert.are.same(
		static,
		exec_lua(
			'return ls.parser.parse_snippet("trig", '
				.. snip_str
				.. "):get_static_text()"
		)
	)
end

return M
