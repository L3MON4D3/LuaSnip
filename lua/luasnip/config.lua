local types = require("luasnip.util.types")

local defaults = {
	history = false,
	updateevents = "InsertLeave",
	store_selection_keys = nil, -- Supossed to be the same as the expand shortcut
	ext_opts = {
		[types.textNode] = {
			active = {},
			passive = {}
		},
		[types.insertNode] = {
			active = {},
			passive = {}
		},
		[types.functionNode] = {
			active = {},
			passive = {}
		},
		[types.snippetNode] = {
			active = {},
			passive = {}
		},
		[types.choiceNode] = {
			active = {},
			passive = {}
		},
		[types.dynamicNode] = {
			active = {},
			passive = {}
		},
		[types.snippet] = {
			active = {},
			passive = {}
		}
	}
}

-- declare here to use in set_config.
local c

c = {
	config = vim.deepcopy(defaults),
	set_config = function(user_config)
		local conf = vim.deepcopy(defaults)

		-- overwrite default ext_opts for each type.
		conf.ext_opts = vim.tbl_extend("force", conf.ext_opts, user_config.ext_opts or {})

		for k, v in pairs(user_config) do
			conf[k] = v
		end
		c.config = conf
		c._setup()
	end,

	_setup = function()
		vim.cmd(string.format(
			[[
        augroup luasnip
            au!
            autocmd %s * lua require("luasnip").active_update_dependents()
			"Remove buffers' nodes on deletion+wipeout.
			autocmd BufDelete,BufWipeout * lua if Luasnip_current_nodes then Luasnip_current_nodes[tonumber(vim.fn.expand("<abuf>"))] = nil end
        augroup END
      ]],
			c.config.updateevents
		))
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
