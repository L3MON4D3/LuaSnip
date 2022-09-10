local util = require("luasnip.util.util")

local M = {}

function M.line_begin(line_to_cursor, matched_trigger)
	-- +1 because `string.sub("abcd", 1, -2)` -> abc
	return line_to_cursor:sub(1, -(#matched_trigger + 1)):match("^%s*$")
end

local function iter_containing_nodes(tree, range)
	-- has to be checked here, manually, named_node_for_range will error if range does not exist.
	if not tree:contains(range) then
		return function()
			return nil
		end
	end

	local current = tree:named_node_for_range(range, {
		-- handled outside of this.
		ignore_injections = true
	})

	return function()
		if not current then
			return nil
		end

		local re = current
		current = current:parent()
		return re
	end
end

local function iter_ts_parent_nodes(range)
	-- get outermost tree.
	local has_parser, parser = pcall(vim.treesitter.get_parser)
	if not has_parser then
		return nil
	end

	-- tree:children only returns one tree?? List them manually...
	local iterators = {iter_containing_nodes(parser, range)}

	-- insert iterators for children
	parser:for_each_child(function(tree)
		table.insert(iterators, iter_containing_nodes(tree, range))
	end)

	-- keep track of iterator for current tree.
	local current_iterator_indx = 1

	return function()
		local node
		while true do
			node = iterators[current_iterator_indx]()

			if not node then
				-- try next iterator (via while).
				-- (it's possible some trees don't contain the range => the
				-- iterators return nil. Since another iterator might contain
				-- the range, we have to loop until we find an iterator that
				-- returns a node, or have tried all iterators.)
				current_iterator_indx = current_iterator_indx + 1

				if current_iterator_indx > #iterators then
					-- all iterators exhausted, return nil.
					return nil
				end
			else
				return node
			end
		end
	end
end

function M.parent_node_matches(predicate)
	local cursor = util.get_cursor_0ind()
	local range = {cursor[1], cursor[2], cursor[1], cursor[2]}

	for node in iter_ts_parent_nodes(range) do
		print(node:type())
	end
end

return M
