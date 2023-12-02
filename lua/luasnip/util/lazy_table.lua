return function(lazy_t, lazy_defs)
	return setmetatable(lazy_t, {
		__index = function(t, k)
			local v = lazy_defs[k]
			if v then
				local v_resolved = v()
				rawset(t, k, v_resolved)
				return v_resolved
			end
			return nil
		end,
	})
end
