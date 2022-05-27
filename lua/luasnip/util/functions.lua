return {
	var = function(_, _, node, text)
		local v = node.parent.snippet.env[text]
		if type(v) == "table" then
			-- Avoid issues with empty vars
			if #v > 0 then
				return v
			else
				return { "" }
			end
		else
			return { v }
		end
	end,
	better_var = function(varname)
		return function(_, parent)
			local v = parent.snippet.env[varname]
			if type(v) == "table" then
				-- Avoid issues with empty vars
				if #v > 0 then
					return v
				else
					return { "" }
				end
			else
				return { v }
			end
		end
	end,
	eval_vim = function(vimstring)
		return function()
			-- 'echo'd string is returned to lua.
			return vim.split(
				vim.api.nvim_exec("echo " .. vimstring, true),
				"\n"
			)
		end
	end,
	copy = function(args)
		return args[1]
	end,
}
