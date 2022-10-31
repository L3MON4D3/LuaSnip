local types = require("luasnip.util.types")
local ext_util = require("luasnip.util.ext_opts")
local ft_functions = require("luasnip.extras.filetype_functions")
local session = require("luasnip.session")
local iNode = require("luasnip.nodes.insertNode")
local cNode = require("luasnip.nodes.choiceNode")

-- Inserts a insert(1) before all other nodes, decreases node.pos's as indexing is "wrong".
local function modify_nodes(snip)
	for i = #snip.nodes, 1, -1 do
		snip.nodes[i + 1] = snip.nodes[i]
		local node = snip.nodes[i + 1]
		if node.pos then
			node.pos = node.pos + 1
		end
	end
	snip.nodes[1] = iNode.I(1)
end

local defaults = {
	history = false,
	update_events = "InsertLeave",
	-- see :h User, event should never be triggered(except if it is `doautocmd`'d)
	region_check_events = "User None",
	delete_check_events = "User None",
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
	-- default applied in util.parser, requires iNode, cNode
	-- (Dependency cycle if here).
	parser_nested_assembler = function(pos, snip)
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
	snip_env = {
		s = require("luasnip.nodes.snippet").S,
		sn = require("luasnip.nodes.snippet").SN,
		isn = require("luasnip.nodes.snippet").ISN,
		t = require("luasnip.nodes.textNode").T,
		i = require("luasnip.nodes.insertNode").I,
		f = require("luasnip.nodes.functionNode").F,
		c = require("luasnip.nodes.choiceNode").C,
		d = require("luasnip.nodes.dynamicNode").D,
		r = require("luasnip.nodes.restoreNode").R,
		events = require("luasnip.util.events"),
		ai = require("luasnip.nodes.absolute_indexer"),
		extras = require("luasnip.extras"),
		l = require("luasnip.extras").lambda,
		rep = require("luasnip.extras").rep,
		p = require("luasnip.extras").partial,
		m = require("luasnip.extras").match,
		n = require("luasnip.extras").nonempty,
		dl = require("luasnip.extras").dynamic_lambda,
		fmt = require("luasnip.extras.fmt").fmt,
		fmta = require("luasnip.extras.fmt").fmta,
		conds = require("luasnip.extras.expand_conditions"),
		postfix = require("luasnip.extras.postfix").postfix,
		types = require("luasnip.util.types"),
		parse = require("luasnip.util.parser").parse_snippet,
	},
}

-- declare here to use in set_config.
local c
session.config = vim.deepcopy(defaults)

c = {
	set_config = function(user_config)
		local conf = vim.deepcopy(defaults)

		-- remove unused highlights from default-ext_opts.
		ext_util.clear_invalid(conf.ext_opts)
		conf.ext_opts = ext_util.child_complete(conf.ext_opts)
		user_config.ext_opts =
			ext_util.child_complete(user_config.ext_opts or {})
		ext_util.child_extend(user_config.ext_opts, conf.ext_opts)

		-- use value from update_events, then updateevents.
		-- also nil updateevents, don't spill it into the main config.
		user_config.update_events = user_config.update_events
			or user_config.updateevents
		user_config.updateevents = nil

		for k, v in pairs(user_config) do
			conf[k] = v
		end

		session.config = conf
		c._setup()
	end,

	_setup = function()
		vim.cmd(
			string.format(
				[[
        augroup luasnip
            au!
            autocmd %s * lua require("luasnip").unlink_current_if_deleted()
            autocmd %s * lua require("luasnip").active_update_dependents()
            autocmd %s * lua require("luasnip").exit_out_of_region(require("luasnip").session.current_nodes[vim.api.nvim_get_current_buf()])
			"Remove buffers' nodes on deletion+wipeout.
			autocmd BufDelete,BufWipeout * lua current_nodes = require("luasnip").session.current_nodes if current_nodes then current_nodes[tonumber(vim.fn.expand("<abuf>"))] = nil end
		]]
					.. (session.config.enable_autosnippets and [[
			autocmd InsertCharPre * lua Luasnip_just_inserted = true
			autocmd TextChangedI,TextChangedP * lua if Luasnip_just_inserted then require("luasnip").expand_auto() Luasnip_just_inserted=nil end
		]] or "")
					.. [[
		augroup END
		]],
				session.config.delete_check_events,
				session.config.update_events,
				session.config.region_check_events
			)
		)
		if session.config.store_selection_keys then
			vim.cmd(
				string.format(
					[[xnoremap <silent>  %s  :lua require('luasnip.util.util').store_selection()<cr>gv"_s]],
					session.config.store_selection_keys
				)
			)
		end
	end,
}

-- Keep these two for backward compativility
c.setup = c.set_config

return c
