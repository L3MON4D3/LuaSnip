local M = {}

function M.line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end

function M.node_types(node_types)

	local ts_utils = require'nvim-treesitter.ts_utils'
	local node_types = type(node_types) == "table" and node_types or { node_types }

	local function cond()
		local node = ts_utils.get_node_at_cursor()
                if node ~= nil then
		        for _, node_type in ipairs(node_types) do
			        if node_type == node:type() then
				        return true
			        end
		        end
                end
		return false
	end

	return cond
end

return M
