local types = require("luasnip.util.types")
local lazy_table = require("luasnip.util.lazy_table")

local ft_functions = require("luasnip.extras.filetype_functions")

-- Inserts a insert(1) before all other nodes, decreases node.pos's as indexing is "wrong".
local function modify_nodes(snip)
	for i = #snip.nodes, 1, -1 do
		snip.nodes[i + 1] = snip.nodes[i]
		local node = snip.nodes[i + 1]
		if node.pos then
			node.pos = node.pos + 1
		end
	end

	local iNode = require("luasnip.nodes.insertNode")
	snip.nodes[1] = iNode.I(1)
end

local lazy_snip_env = {
	s = function()
		return require("luasnip.nodes.snippet").S
	end,
	sn = function()
		return require("luasnip.nodes.snippet").SN
	end,
	isn = function()
		return require("luasnip.nodes.snippet").ISN
	end,
	t = function()
		return require("luasnip.nodes.textNode").T
	end,
	i = function()
		return require("luasnip.nodes.insertNode").I
	end,
	f = function()
		return require("luasnip.nodes.functionNode").F
	end,
	c = function()
		return require("luasnip.nodes.choiceNode").C
	end,
	d = function()
		return require("luasnip.nodes.dynamicNode").D
	end,
	r = function()
		return require("luasnip.nodes.restoreNode").R
	end,
	events = function()
		return require("luasnip.util.events")
	end,
	ai = function()
		return require("luasnip.nodes.absolute_indexer")
	end,
	extras = function()
		return require("luasnip.extras")
	end,
	l = function()
		return require("luasnip.extras").lambda
	end,
	rep = function()
		return require("luasnip.extras").rep
	end,
	p = function()
		return require("luasnip.extras").partial
	end,
	m = function()
		return require("luasnip.extras").match
	end,
	n = function()
		return require("luasnip.extras").nonempty
	end,
	dl = function()
		return require("luasnip.extras").dynamic_lambda
	end,
	fmt = function()
		return require("luasnip.extras.fmt").fmt
	end,
	fmta = function()
		return require("luasnip.extras.fmt").fmta
	end,
	conds = function()
		return require("luasnip.extras.expand_conditions")
	end,
	postfix = function()
		return require("luasnip.extras.postfix").postfix
	end,
	types = function()
		return require("luasnip.util.types")
	end,
	parse = function()
		return require("luasnip.util.parser").parse_snippet
	end,
	ms = function()
		return require("luasnip.nodes.multiSnippet").new_multisnippet
	end,
}

-- stylua: ignore
return {
	-- corresponds to legacy "history=false".
	keep_roots = false,
	link_roots = false,
	link_children = false,

	update_events = "InsertLeave",
	-- see :h User, event should never be triggered(except if it is `doautocmd`'d)
	region_check_events = nil,
	delete_check_events = nil,
	store_selection_keys = nil, -- Supossed to be the same as the expand shortcut
	ext_opts = {
		[types.textNode] = {
			active = { hl_group = "LuasnipTextNodeActive" },
			passive = { hl_group = "LuasnipTextNodePassive" },
			visited = { hl_group = "LuasnipTextNodeVisited" },
			unvisited = { hl_group = "LuasnipTextNodeUnvisited" },
			snippet_passive = { hl_group = "LuasnipTextNodeSnippetPassive" },
		},
		[types.insertNode] = {
			active = { hl_group = "LuasnipInsertNodeActive" },
			passive = { hl_group = "LuasnipInsertNodePassive" },
			visited = { hl_group = "LuasnipInsertNodeVisited" },
			unvisited = { hl_group = "LuasnipInsertNodeUnvisited" },
			snippet_passive = {
				hl_group = "LuasnipInsertNodeSnippetPassive",
			},
		},
		[types.exitNode] = {
			active = { hl_group = "LuasnipExitNodeActive" },
			passive = { hl_group = "LuasnipExitNodePassive" },
			visited = { hl_group = "LuasnipExitNodeVisited" },
			unvisited = { hl_group = "LuasnipExitNodeUnvisited" },
			snippet_passive = { hl_group = "LuasnipExitNodeSnippetPassive" },
		},
		[types.functionNode] = {
			active = { hl_group = "LuasnipFunctionNodeActive" },
			passive = { hl_group = "LuasnipFunctionNodePassive" },
			visited = { hl_group = "LuasnipFunctionNodeVisited" },
			unvisited = { hl_group = "LuasnipFunctionNodeUnvisited" },
			snippet_passive = {
				hl_group = "LuasnipFunctionNodeSnippetPassive",
			},
		},
		[types.snippetNode] = {
			active = { hl_group = "LuasnipSnippetNodeActive" },
			passive = { hl_group = "LuasnipSnippetNodePassive" },
			visited = { hl_group = "LuasnipSnippetNodeVisited" },
			unvisited = { hl_group = "LuasnipSnippetNodeUnvisited" },
			snippet_passive = {
				hl_group = "LuasnipSnippetNodeSnippetPassive",
			},
		},
		[types.choiceNode] = {
			active = { hl_group = "LuasnipChoiceNodeActive" },
			passive = { hl_group = "LuasnipChoiceNodePassive" },
			visited = { hl_group = "LuasnipChoiceNodeVisited" },
			unvisited = { hl_group = "LuasnipChoiceNodeUnvisited" },
			snippet_passive = {
				hl_group = "LuasnipChoiceNodeSnippetPassive",
			},
		},
		[types.dynamicNode] = {
			active = { hl_group = "LuasnipDynamicNodeActive" },
			passive = { hl_group = "LuasnipDynamicNodePassive" },
			visited = { hl_group = "LuasnipDynamicNodeVisited" },
			unvisited = { hl_group = "LuasnipDynamicNodeUnvisited" },
			snippet_passive = {
				hl_group = "LuasnipDynamicNodeSnippetPassive",
			},
		},
		[types.snippet] = {
			active = { hl_group = "LuasnipSnippetActive" },
			passive = { hl_group = "LuasnipSnippetPassive" },
			-- not used!
			visited = { hl_group = "LuasnipSnippetVisited" },
			unvisited = { hl_group = "LuasnipSnippetUnvisited" },
			snippet_passive = { hl_group = "LuasnipSnippetSnippetPassive" },
		},
		[types.restoreNode] = {
			active = { hl_group = "LuasnipRestoreNodeActive" },
			passive = { hl_group = "LuasnipRestoreNodePassive" },
			visited = { hl_group = "LuasnipRestoreNodeVisited" },
			unvisited = { hl_group = "LuasnipRestoreNodeUnvisited" },
			snippet_passive = {
				hl_group = "LuasnipRestoreNodeSnippetPassive",
			},
		},
	},
	ext_base_prio = 200,
	ext_prio_increase = 9,
	enable_autosnippets = false,
	parser_nested_assembler = function(pos, snip)
		-- only require here, to prevent some upfront load-cost.
		local iNode = require("luasnip.nodes.insertNode")
		local cNode = require("luasnip.nodes.choiceNode")

		modify_nodes(snip)
		snip:init_nodes()
		snip.pos = nil

		return cNode.C(pos, { snip, iNode.I(nil, { "" }) })
	end,
	-- Function expected to return a list of filetypes (or empty list)
	ft_func = ft_functions.from_filetype,
	-- fn(bufnr) -> string[] (filetypes).
	load_ft_func = ft_functions.from_filetype_load,
	-- globals injected into luasnippet-files.
	snip_env = lazy_table({}, lazy_snip_env),
	loaders_store_source = false,
}
