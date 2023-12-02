local ext_util = require("luasnip.util.ext_opts")
local session = require("luasnip.session")
local conf_defaults = require("luasnip.default_config")

local function set_snip_env(target_conf_defaults, user_config)
	if not user_config.snip_env then
		-- target_conf already contains defaults
		return
	end

	-- either "set" or "extend", make sure it does not appear in the final snip_env.
	local snip_env_behaviour = user_config.snip_env.__snip_env_behaviour ~= nil
			and user_config.snip_env.__snip_env_behaviour
		or "extend"
	assert(
		snip_env_behaviour == "set" or snip_env_behaviour == "extend",
		"Unknown __snip_env_behaviour, `" .. snip_env_behaviour .. "`"
	)
	user_config.snip_env.__snip_env_behaviour = nil

	if snip_env_behaviour == "set" then
		target_conf_defaults.snip_env = user_config.snip_env
	else
		-- cannot use vim.tbl_extend, since we'd need to transfer the metatable.
		for k, v in pairs(user_config.snip_env) do
			target_conf_defaults.snip_env[k] = v
		end
	end

	-- set to nil, to mark that it's handled.
	user_config.snip_env = nil
end

-- declare here to use in set_config.
local c

c = {
	set_config = function(user_config)
		user_config = user_config or {}
		local conf = vim.deepcopy(conf_defaults)

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

		set_snip_env(conf, user_config)

		-- handle legacy-key history.
		if user_config.history ~= nil then
			conf.keep_roots = user_config.history
			conf.link_roots = user_config.history
			conf.link_children = user_config.history

			-- unset key to prevent handling twice.
			conf.history = nil
		end

		for k, v in pairs(user_config) do
			conf[k] = v
		end

		session.config = conf
		c._setup()
	end,

	_setup = function()
		local augroup = vim.api.nvim_create_augroup("luasnip", {})

		-- events: string[], or string. if string[], each string is one
		-- event-name, if string, either one event-name, or multiple delimited by `,`.
		local function ls_autocmd(events, callback)
			if type(events) == "string" then
				-- split on ',' for backwards compatibility.
				-- remove spaces from string.
				events = vim.split(events:gsub(" ", ""), ",")
			end
			vim.api.nvim_create_autocmd(events, {
				callback = callback,
				group = augroup,
			})
		end
		if session.config.delete_check_events ~= nil then
			ls_autocmd(
				session.config.delete_check_events,
				require("luasnip").unlink_current_if_deleted
			)
		end
		ls_autocmd(
			session.config.update_events,
			require("luasnip").active_update_dependents
		)
		if session.config.region_check_events ~= nil then
			ls_autocmd(session.config.region_check_events, function()
				require("luasnip").exit_out_of_region(
					require("luasnip").session.current_nodes[vim.api.nvim_get_current_buf()]
				)
			end)
		end
		-- Remove buffers' nodes on deletion+wipeout.
		ls_autocmd({ "BufDelete", "BufWipeout" }, function(event)
			local current_nodes = require("luasnip").session.current_nodes
			if current_nodes then
				current_nodes[event.buf] = nil
			end
		end)
		if session.config.enable_autosnippets then
			ls_autocmd("InsertCharPre", function()
				Luasnip_just_inserted = true
			end)
			ls_autocmd({ "TextChangedI", "TextChangedP" }, function()
				if Luasnip_just_inserted then
					require("luasnip").expand_auto()
					Luasnip_just_inserted = nil
				end
			end)
		end

		if session.config.store_selection_keys then
			vim.cmd(
				string.format(
					[[xnoremap <silent>  %s  %s]],
					session.config.store_selection_keys,
					require("luasnip.util.select").select_keys
				)
			)
		end
	end,
}

-- Keep these two for backward compativility
c.setup = c.set_config

return c
