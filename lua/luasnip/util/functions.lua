return {
	var = function(_, node, text)
		local v = node.parent.env[text]
		if type(v) == "table" then
			return v
		else
			return { v }
		end
	end,
	copy = function(args)
		return args[1]
	end,
}
