local snip_mod = require("luasnip.nodes.snippet")
local node_util = require("luasnip.nodes.util")
local extend_decorator = require("luasnip.util.extend_decorator")

local VirtualSnippet = {}
local VirtualSnippet_mt = { __index = VirtualSnippet }

function VirtualSnippet:get_docstring()
	return self.snippet:get_docstring()
end
function VirtualSnippet:copy()
	local copy = self.snippet:copy()
	copy.id = self.id

	return copy
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

local function multisnippet_from_snippet_obj(contexts, snippet, snippet_opts)
	assert(
		type(contexts) == "table",
		"multisnippet: expected contexts to be a table."
	)
	local common_context = node_util.wrap_context(contexts.common) or {}

	local v_snips = {}
	for _, context in ipairs(contexts) do
		local complete_context = vim.tbl_extend(
			"keep",
			node_util.wrap_context(context),
			common_context
		)
		table.insert(
			v_snips,
			new_virtual_snippet(complete_context, snippet, snippet_opts)
		)
	end

	local o = {
		v_snips = v_snips,
	}

	setmetatable(o, MultiSnippet_mt)

	return o
end

local function multisnippet_from_nodes(contexts, nodes, opts)
	opts = opts or {}
	local common_snip_opts = opts.common_opts or {}

	-- create snippet without `context`-fields!
	-- compare to `S` (aka `s`, the default snippet-constructor) in
	-- `nodes/snippet.lua`.
	return multisnippet_from_snippet_obj(
		contexts,
		snip_mod._S(
			snip_mod.init_snippet_opts(common_snip_opts),
			nodes,
			common_snip_opts
		),
		common_snip_opts
	)
end

local function extend_multisnippet_contexts(passed_arg, extend_arg)
	-- extend passed arg with contexts passed in extend-call
	vim.list_extend(passed_arg, extend_arg)

	-- extend ("keep") valid keyword-arguments.
	passed_arg.common = vim.tbl_deep_extend(
		"keep",
		node_util.wrap_context(passed_arg.common) or {},
		node_util.wrap_context(extend_arg.common) or {}
	)

	return passed_arg
end
extend_decorator.register(
	multisnippet_from_nodes,
	-- first arg needs special handling (extend list of contexts (index i
	-- becomes i+#passed_arg, not i again))
	{ arg_indx = 1, extend = extend_multisnippet_contexts },
	-- opts can just be `vim.tbl_extend`ed.
	{ arg_indx = 3 }
)

return {
	new_multisnippet = multisnippet_from_nodes,
	_raw_ms = multisnippet_from_snippet_obj,
}
