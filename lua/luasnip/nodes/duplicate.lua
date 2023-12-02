local snip_mod = require("luasnip.nodes.snippet")

local M = {}

local DupExpandable = {}

-- just pass these through to _expandable.
function DupExpandable:get_docstring()
	return self._expandable:get_docstring()
end
function DupExpandable:copy()
	local copy = self._expandable:copy()
	copy.id = self.id

	return copy
end

-- this is modified in `self:invalidate` _and_ needs to be called on _expandable.
function DupExpandable:matches(...)
	-- use snippet-module matches, self._expandable might have had its match
	-- overwritten by invalidate.
	-- (if there are more issues with this, consider some other mechanism for
	-- invalidating)
	return snip_mod.Snippet.matches(self._expandable, ...)
end

-- invalidate has to be called on this snippet itself.
function DupExpandable:invalidate()
	snip_mod.Snippet.invalidate(self)
end

local dup_mt = {
	-- index DupExpandable for own functions, and then the expandable stored in
	-- self/t.
	__index = function(t, k)
		if DupExpandable[k] then
			return DupExpandable[k]
		end

		return t._expandable[k]
	end,
}

function M.duplicate_expandable(expandable)
	return setmetatable({
		_expandable = expandable,
		-- copy these!
		-- if `expandable` is invalidated, we don't necessarily want this
		-- expandable to be invalidated as well.
		hidden = expandable.hidden,
		invalidated = expandable.invalidated,
	}, dup_mt)
end

local DupAddable = {}

function DupAddable:retrieve_all()
	-- always return the same set of items, necessary when for invalidate via
	-- key to work correctly.
	return self._all
end
local DupAddable_mt = {
	__index = DupAddable,
}

function M.duplicate_addable(addable)
	return setmetatable({
		addable = addable,
		_all = vim.tbl_map(M.duplicate_expandable, addable:retrieve_all()),
	}, DupAddable_mt)
end

return M
