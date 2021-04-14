local defaults = {
	history = false
}

-- declare here to use in set_config.
local c

c = {
	config = defaults,
	set_config = function(user_config)
		local conf = vim.deepcopy(defaults)
		for k, v in ipairs(user_config) do
			conf[k] = v
		end
		c.config = conf
	end
}

return c
