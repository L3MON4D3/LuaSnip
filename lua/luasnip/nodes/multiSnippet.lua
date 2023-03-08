local snip_mod = require("luasnip.nodes.snippet")
local node_util = require("luasnip.nodes.util")

local VirtualSnippet = {}
local VirtualSnippet_mt = { __index = VirtualSnippet }

function VirtualSnippet:get_docstring()
	return self.snippet:get_docstring()
end
function VirtualSnippet:copy()
	return self.snippet:copy()
end

-- VirtualSnippet has all the fields for executing these methods.
VirtualSnippet.matches = snip_mod.Snippet.matches
VirtualSnippet.invalidate = snip_mod.Snippet.invalidate

---Create new virtual snippet, ie. an object which is capable of performning
---all the functions expected from a snippet which is yet to be expanded
---(`matches`,`get_docstring`,`invalidate`,`retrieve_all`,`copy`)
---@param context context as defined for snippet-constructor. Table, not nil.
---@param snippet The snippet this virtual snippet will return on `copy`, also not nil.
---@param opts opts as defined for snippet-constructor. Has to be a table, may be empty.
local function new_virtual_snippet(context, snippet, opts)
	-- init fields necessary for matches, invalidate, adding the snippet.
	local o = snip_mod.init_snippet_context(context, opts)
	o.snippet = snippet

	setmetatable(o, VirtualSnippet_mt)

	return o
end

local MultiSnippet = {}
local MultiSnippet_mt = { __index = MultiSnippet }

function MultiSnippet:retrieve_all()
	return self.v_snips
end

local function new_multisnippet(contexts, nodes, opts)
	assert(
		type(contexts) == "table",
		"multisnippet: expected contexts to be a table."
	)
	opts = opts or {}
	local common_snip_opts = opts.common_opts or {}

	local common_context = node_util.wrap_context(contexts.common) or {}

	-- create snippet without `context`-fields!
	-- compare to `S` (aka `s`, the default snippet-constructor) in
	-- `nodes/snippet.lua`.
	local snippet = snip_mod._S(
		snip_mod.init_snippet_opts(common_snip_opts),
		nodes,
		common_snip_opts
	)

	local v_snips = {}
	for _, context in ipairs(contexts) do
		local complete_context = vim.tbl_extend(
			"keep",
			node_util.wrap_context(context),
			common_context
		)
		table.insert(
			v_snips,
			new_virtual_snippet(complete_context, snippet, common_snip_opts)
		)
	end

	local o = {
		v_snips = v_snips,
	}

	setmetatable(o, MultiSnippet_mt)

	return o
end

return {
	new_multisnippet = new_multisnippet,
}
