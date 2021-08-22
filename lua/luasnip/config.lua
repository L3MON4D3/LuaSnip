local types = require("luasnip.util.types")
local util = require("luasnip.util.util")

local defaults = {
	history = false,
	updateevents = "InsertLeave",
	-- see :h User, event should never be triggered(except if it is `doautocmd`'d)
	region_check_events = "User None",
	store_selection_keys = nil, -- Supossed to be the same as the expand shortcut
	ext_opts = {
		[types.textNode] = {
			active = { hl_group = "LuasnipTextNodeActive" },
			passive = { hl_group = "LuasnipTextNodePassive" },
		},
		[types.insertNode] = {
			active = { hl_group = "LuasnipInsertNodeActive" },
			passive = { hl_group = "LuasnipInsertNodePassive" },
		},
		[types.exitNode] = {
			active = { hl_group = "LuasnipExitNodeActive" },
			passive = { hl_group = "LuasnipExitNodePassive" },
		},
		[types.functionNode] = {
			active = { hl_group = "LuasnipFunctionNodeActive" },
			passive = { hl_group = "LuasnipFunctionNodePassive" },
		},
		[types.snippetNode] = {
			active = { hl_group = "LuasnipSnippetNodeActive" },
			passive = { hl_group = "LuasnipSnippetNodePassive" },
		},
		[types.choiceNode] = {
			active = { hl_group = "LuasnipChoiceNodeActive" },
			passive = { hl_group = "LuasnipChoiceNodePassive" },
		},
		[types.dynamicNode] = {
			active = { hl_group = "LuasnipDynamicNodeActive" },
			passive = { hl_group = "LuasnipDynamicNodePassive" },
		},
		[types.snippet] = {
			active = { hl_group = "LuasnipSnippetActive" },
			passive = { hl_group = "LuasnipSnippetPassive" },
		},
	},
	ext_base_prio = 200,
	ext_prio_increase = 7,
	enable_autosnippets = false,
}

-- declare here to use in set_config.
local c

c = {
	config = vim.deepcopy(defaults),
	set_config = function(user_config)
		local conf = vim.deepcopy(defaults)

		util.clear_invalid(conf.ext_opts)

		user_config.ext_opts = util.make_opts_valid(
			user_config.ext_opts or {},
			conf.ext_opts
		)
		util.increase_ext_prio(
			user_config.ext_opts,
			user_config.ext_base_prio or conf.ext_base_prio
		)

		for k, v in pairs(user_config) do
			conf[k] = v
		end
		c.config = conf
		c._setup()
	end,

	_setup = function()
		vim.cmd(string.format([[
        augroup luasnip
            au!
            autocmd %s * lua require("luasnip").active_update_dependents()
            autocmd %s * lua require("luasnip").exit_out_of_region(Luasnip_current_nodes[vim.api.nvim_get_current_buf()])
			"Remove buffers' nodes on deletion+wipeout.
			autocmd BufDelete,BufWipeout * lua if Luasnip_current_nodes then Luasnip_current_nodes[tonumber(vim.fn.expand("<abuf>"))] = nil end
		]] .. (c.config.enable_autosnippets and [[
			autocmd InsertCharPre * lua Luasnip_just_inserted = true
			autocmd TextChangedI * lua if Luasnip_just_inserted then require("luasnip").expand_auto() Luasnip_just_inserted=false end
		]] or "") .. [[
		augroup END
		]], c.config.updateevents, c.config.region_check_events))
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
