-- the idea of this class is to lazily parse snippet (eg. only on expansion).
--
-- This is achieved by returning a proxy that has enough information to tell
-- whether the snippet should be expanded at a given point (eg. all fields
-- necessary to perform Snippet:matches()), but doesn't actually
-- have to parse the snippet, leaving up-front cost of loading a bunch of
-- snippets at a minimum.

local lsp_parse_fn = require("luasnip.util.parser").parse_snippet
local snip_mod = require("luasnip.nodes.snippet")
local node_util = require("luasnip.nodes.util")
local extend_decorator = require("luasnip.util.extend_decorator")

local SnippetProxy = {}

-- add Snippet-functions SnippetProxy can perform using the available data.
SnippetProxy.matches = snip_mod.Snippet.matches
SnippetProxy.invalidate = snip_mod.Snippet.invalidate
SnippetProxy.retrieve_all = snip_mod.Snippet.retrieve_all

function SnippetProxy:get_docstring()
	return self.docstring
end

function SnippetProxy:instantiate(parse_fn)
	-- self already contains initialized context and opts, can just be passed
	-- here, no problem.
	-- Bonus: if some keys are set on the snippets in the table (from the
	-- outside, for whatever reason), they are also present in the expanded
	-- snippet.
	--
	-- _S will copy self, so we can safely mutate (set metatables).
	local snippet = snip_mod._S(self, parse_fn(nil, self._snippet_string))
	-- snippet will have snippetProxies `copy`, nil it in snippet so it calls
	-- snippet-copy via metatable.
	snippet.copy = nil

	self._snippet = snippet
	-- directly call into snippet on missing keys.
	setmetatable(self, {
		__index = self._snippet,
	})

	-- return snippet so it can provide a missing key.
	return snippet
end

-- some values of the snippet are nil by default, list them here so snippets
-- aren't instantiated because of them.
local license_to_nil =
	{ priority = true, snippetType = true, _source = true, filetype = true }

-- context and opts are (almost) the same objects as in s(contex, nodes, opts), snippet is a string representing the snippet.
-- opts can aditionally contain the key `parse_fn`, which will be used to parse
-- the snippet. This is useful, since snipmate-snippets are parsed with a
-- function than regular lsp-snippets.
-- context can be nil, in that case the resulting object can't be inserted into
-- the snippet-tables, but may be used after expansion (i.e. returned from
-- snippet:copy)
local function new(context, snippet, opts)
	opts = opts or {}

	-- default to regular lsp-parse-function.
	local parse_fn = lsp_parse_fn

	if opts.parse_fn then
		parse_fn = opts.parse_fn
	end
	-- "error": there should not be duplicate keys, don't silently overwrite/keep.
	local sp = vim.tbl_extend(
		"error",
		{},
		context
				and snip_mod.init_snippet_context(
					node_util.wrap_context(context),
					opts
				)
			or {},
		snip_mod.init_snippet_opts(opts),
		node_util.init_node_opts(opts)
	)

	sp._snippet_string = snippet
	-- override docstring
	sp.docstring = snippet

	setmetatable(sp, {
		__index = function(t, k)
			if license_to_nil[k] then
				-- k might be nil, return it.
				return nil
			end

			if SnippetProxy[k] then
				-- if it is possible to perform this operation without actually parsing the snippet, just do it.
				return SnippetProxy[k]
			end
			local snip = SnippetProxy.instantiate(t, parse_fn)
			if k == "_snippet" then
				return snip
			else
				return snip[k]
			end
		end,
	})

	-- snippetProxy has to be able to return snippet on copy even after parsing,
	-- when the metatable has been changed. Therefore: set copy in each instance
	-- of snippetProxy.
	function sp:copy()
		local copy = self._snippet:copy()
		copy.id = self.id

		return copy
	end

	return sp
end
extend_decorator.register(
	new,
	{ arg_indx = 1, extend = node_util.snippet_extend_context },
	{ arg_indx = 3 }
)

return new
