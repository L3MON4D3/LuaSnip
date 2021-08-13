local types = require("luasnip.util.types")
local util = require("luasnip.util.util")

local defaults = {
	history = false,
	updateevents = "InsertLeave",
	store_selection_keys = nil, -- Supossed to be the same as the expand shortcut
	ext_opts = {
		[types.textNode] = {
			active = {},
			passive = {},
		},
		[types.insertNode] = {
			active = {},
			passive = {},
		},
		[types.functionNode] = {
			active = {},
			passive = {},
		},
		[types.snippetNode] = {
			active = {},
			passive = {},
		},
		[types.choiceNode] = {
			active = {},
			passive = {},
		},
		[types.dynamicNode] = {
			active = {},
			passive = {},
		},
		[types.snippet] = {
			active = {},
			passive = {},
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

		user_config.ext_opts = util.make_opts_valid(
			user_config.ext_opts or {},
			defaults.ext_opts
		)
		util.increase_ext_prio(
			user_config.ext_opts,
			user_config.ext_base_prio or defaults.ext_base_prio
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
			"Remove buffers' nodes on deletion+wipeout.
			autocmd BufDelete,BufWipeout * lua if Luasnip_current_nodes then Luasnip_current_nodes[tonumber(vim.fn.expand("<abuf>"))] = nil end
		]] .. (c.config.enable_autosnippets and [[
			autocmd InsertCharPre * lua Luasnip_just_inserted = true
			autocmd TextChangedI * lua if Luasnip_just_inserted then require("luasnip").expand_auto() Luasnip_just_inserted=false end
		]] or "") .. [[
		augroup END
		]], c.config.updateevents))
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
