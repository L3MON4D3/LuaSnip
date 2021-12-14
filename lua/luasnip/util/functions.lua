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
	copy = function(args)
		return args[1]
	end,
}
