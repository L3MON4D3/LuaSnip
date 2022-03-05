local types = require("luasnip.util.types")
local util = require("luasnip.util.util")
local ext_util = require("luasnip.util.ext_opts")
local ft_functions = require("luasnip.extras.filetype_functions")

local defaults = {
	history = false,
	updateevents = "InsertLeave",
	-- see :h User, event should never be triggered(except if it is `doautocmd`'d)
	region_check_events = "User None",
	delete_check_events = "User None",
	store_selection_keys = nil, -- Supossed to be the same as the expand shortcut
	ext_opts = {
		[types.textNode] = {
			active = { hl_group = "LuasnipTextNodeActive" },
			passive = { hl_group = "LuasnipTextNodePassive" },
			snippet_passive = { hl_group = "LuasnipTextNodeSnippetPassive" },
		},
		[types.insertNode] = {
			active = { hl_group = "LuasnipInsertNodeActive" },
			passive = { hl_group = "LuasnipInsertNodePassive" },
			snippet_passive = {
				hl_group = "LuasnipInsertNodeSnippetPassive",
			},
		},
		[types.exitNode] = {
			active = { hl_group = "LuasnipExitNodeActive" },
			passive = { hl_group = "LuasnipExitNodePassive" },
			snippet_passive = { hl_group = "LuasnipExitNodeSnippetPassive" },
		},
		[types.functionNode] = {
			active = { hl_group = "LuasnipFunctionNodeActive" },
			passive = { hl_group = "LuasnipFunctionNodePassive" },
			snippet_passive = {
				hl_group = "LuasnipFunctionNodeSnippetPassive",
			},
		},
		[types.snippetNode] = {
			active = { hl_group = "LuasnipSnippetNodeActive" },
			passive = { hl_group = "LuasnipSnippetNodePassive" },
			snippet_passive = {
				hl_group = "LuasnipSnippetNodeSnippetPassive",
			},
		},
		[types.choiceNode] = {
			active = { hl_group = "LuasnipChoiceNodeActive" },
			passive = { hl_group = "LuasnipChoiceNodePassive" },
			snippet_passive = {
				hl_group = "LuasnipChoiceNodeSnippetPassive",
			},
		},
		[types.dynamicNode] = {
			active = { hl_group = "LuasnipDynamicNodeActive" },
			passive = { hl_group = "LuasnipDynamicNodePassive" },
			snippet_passive = {
				hl_group = "LuasnipDynamicNodeSnippetPassive",
			},
		},
		[types.snippet] = {
			active = { hl_group = "LuasnipSnippetActive" },
			passive = { hl_group = "LuasnipSnippetPassive" },
			-- not used!
			snippet_passive = { hl_group = "LuasnipSnippetSnippetPassive" },
		},
		[types.restoreNode] = {
			active = { hl_group = "LuasnipRestoreNodeActive" },
			passive = { hl_group = "LuasnipRestoreNodePassive" },
			snippet_passive = {
				hl_group = "LuasnipRestoreNodeSnippetPassive",
			},
		},
	},
	ext_base_prio = 200,
	ext_prio_increase = 7,
	enable_autosnippets = false,
	-- default applied in util.parser, requires iNode, cNode
	-- (Dependency cycle if here).
	parser_nested_assembler = nil,
	-- Function expected to return a list of filetypes (or empty list)
	ft_func = ft_functions.from_filetype,
}

-- declare here to use in set_config.
local c

c = {
	config = vim.deepcopy(defaults),
	set_config = function(user_config)
		local conf = vim.deepcopy(defaults)

		-- remove unused highlights from default-ext_opts.
		ext_util.clear_invalid(conf.ext_opts)
		ext_util.complete(conf.ext_opts)
		user_config.ext_opts = user_config.ext_opts or {}
		ext_util.complete(user_config.ext_opts)
		ext_util.extend(user_config.ext_opts, conf.ext_opts)

		for k, v in pairs(user_config) do
			conf[k] = v
		end

		c.config = conf
		c._setup()
	end,

	_setup = function()
		vim.cmd(
			string.format(
				[[
        augroup luasnip
            au!
            autocmd User LuasnipCleanup lua require("luasnip").snippets = {}
            autocmd %s * lua require("luasnip").unlink_current_if_deleted()
            autocmd %s * lua require("luasnip").active_update_dependents()
            autocmd %s * lua require("luasnip").exit_out_of_region(require("luasnip").session.current_nodes[vim.api.nvim_get_current_buf()])
			"Remove buffers' nodes on deletion+wipeout.
			autocmd BufDelete,BufWipeout * lua current_nodes = require("luasnip").session.current_nodes if current_nodes then current_nodes[tonumber(vim.fn.expand("<abuf>"))] = nil end
		]]
					.. (c.config.enable_autosnippets and [[
			autocmd InsertCharPre * lua Luasnip_just_inserted = true
			autocmd TextChangedI,TextChangedP * lua if Luasnip_just_inserted then require("luasnip").expand_auto() Luasnip_just_inserted=nil end
		]] or "")
					.. [[
		augroup END
		]],
				c.config.delete_check_events,
				c.config.updateevents,
				c.config.region_check_events
			)
		)
		if c.config.store_selection_keys then
			vim.cmd(
				string.format(
					[[xnoremap <silent>  %s  :lua require('luasnip.util.util').store_selection()<cr>gv"_s]],
					c.config.store_selection_keys
				)
			)
		end
	end,
}
c.setup = c.set_config

return c
