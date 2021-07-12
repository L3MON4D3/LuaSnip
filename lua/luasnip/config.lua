local defaults = {
	history = false,
	updateevents = "InsertLeave",
}

-- declare here to use in set_config.
local c

c = {
	config = vim.deepcopy(defaults),
	set_config = function(user_config)
		local conf = vim.deepcopy(defaults)
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
	end,
}
c.setup = c.set_config

return c
