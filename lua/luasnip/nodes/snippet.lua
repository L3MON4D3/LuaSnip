local node_mod = require("luasnip.nodes.node")
local iNode = require("luasnip.nodes.insertNode")
local tNode = require("luasnip.nodes.textNode")
local util = require("luasnip.util.util")
local ext_util = require("luasnip.util.ext_opts")
local node_util = require("luasnip.nodes.util")
local types = require("luasnip.util.types")
local events = require("luasnip.util.events")
local mark = require("luasnip.util.mark").mark
local Environ = require("luasnip.util.environ")
local session = require("luasnip.session")
local pattern_tokenizer = require("luasnip.util.pattern_tokenizer")
local dict = require("luasnip.util.dict")
local snippet_collection = require("luasnip.session.snippet_collection")
local extend_decorator = require("luasnip.util.extend_decorator")
local source = require("luasnip.session.snippet_collection.source")
local loader_util = require("luasnip.loaders.util")
local trig_engines = require("luasnip.nodes.util.trig_engines")

local true_func = function()
	return true
end

---@param condition LuaSnip.SnipContext.Condition
---@param user_resolve LuaSnip.ResolveExpandParamsFn
---@return LuaSnip.ResolveExpandParamsFn
local generate_resolve_expand_params_func = function(condition, user_resolve)
	return function(self, line_to_cursor, match, captures)
		if condition then
			if not condition(line_to_cursor, match, captures) then
				return nil
			end
		end

		---@type LuaSnip.ExpandParams
		local default_expand_params = {
			trigger = match,
			captures = captures,
		}

		if user_resolve then
			local res = user_resolve(self, line_to_cursor, match, captures)
			if res == nil then
				return nil
			end
			return vim.tbl_extend("force", default_expand_params, res)
		else
			return default_expand_params
		end
	end
end

local callbacks_mt = {
	__index = function(table, key)
		rawset(table, key, {})
		return {}
	end,
}

-- declare SN here, is needed in metatable.
local SN

-- TODO(@bew): rename to LuaSnip.CommonSnippetData (?)
---@class LuaSnip.BareInternalSnippet: LuaSnip.Node
---  To be used as a base for all snippet-like nodes (Snippet, SnippetProxy, ..)
---
---@field nodes LuaSnip.Node[]
---@field insert_nodes LuaSnip.InsertNode[]
---
---(FIXME(@bew): these fields are only for ExpandedSnippet?)
---@field snippet LuaSnip.Snippet
---@field dependents table (FIXME(@L3MON4D3): type/doc!)
---@field dependents_dict table (FIXME(@L3MON4D3): type/doc!)
---@field child_snippets table[] (FIXME(@L3MON4D3): type/doc!)
---@field static_text string[]?
---@field indentstr string
local Snippet = node_mod.Node:new()

---@class LuaSnip.Snippet: LuaSnip.BareInternalSnippet, LuaSnip.NormalizedSnippetContext, LuaSnip.NormalizedSnippetOpts, LuaSnip.Addable
---@field _source? LuaSnip.Source
---@field node_store_id integer

-- very approximate classes, for now.
---@alias LuaSnip.SnippetID integer

---Anything that can be passed to ls.add_snippets().
---@class LuaSnip.Addable
---@field retrieve_all (fun(self: LuaSnip.Addable): LuaSnip.Snippet[])
---
---(FIXME(@bew): these fields are only for RegisteredSnippet? (not nil!))
---@field id? integer Internal ID of this snippet (used for source mapping)
---@field effective_priority? integer Effective priority of the added snippet

---Represents an expanded snippet.
---@class LuaSnip.ExpandedSnippet: LuaSnip.Snippet
---@field env table<string, any> Variables used in the LSP-protocol
---  (e.g. `TM_CURRENT_LINE` or `TM_FILENAME`).
---@field trigger string The string that triggered this snipper.
---  Only interesting when the snippet was triggered with a non-"plain"
---  `trigEngine` for getting the full match.
---@field captures string[] The capture-groups when the snippet was triggered
---  with a non-"plain" `trigEngine`.
---
---@field prev LuaSnip.Node
---@field next LuaSnip.Node

---@class LuaSnip.NormalizedSnippetContext
---@field trigger string The trigger of the snippet
---@field name string
---@field description string[]
---@field dscr string[] Same as `description`, kept to avoid breaking downstream
---  usages.
---@field docstring? string[]
---@field priority? integer
---@field snippetType? "snippets"|"autosnippets"
---@field filetype? string
---@field wordTrig boolean
---@field hidden boolean
---@field regTrig boolean
---@field docTrig? string
---@field trig_matcher LuaSnip.SnipContext.TrigMatcher
---@field resolveExpandParams LuaSnip.ResolveExpandParamsFn
---@field show_condition LuaSnip.SnipContext.ShowCondition
---@field condition LuaSnip.SnipContext.Condition
---@field invalidated boolean

---@class LuaSnip.NormalizedSnippetNodeOpts
---@field callbacks {[integer]: {[LuaSnip.EventType]: fun(node: LuaSnip.Node, event_args?: table)}}
---@field child_ext_opts LuaSnip.ChildExtOpts
---@field merge_child_ext_opts boolean

---@class LuaSnip.NormalizedSnippetOpts: LuaSnip.NormalizedSnippetNodeOpts
---@field stored {[string]: LuaSnip.SnippetNode}

-- FIXME(@bew): What is this for? (not documented..)
-- FIXME(@bew): Should be moved to its own file? (like the other indexers)
local Parent_indexer = {}

function Parent_indexer:new(o)
	setmetatable(o, self)
	self.__index = self
	return o
end

-- Returns referred node from parent (or parents' parent).
function Parent_indexer:resolve(snippet)
	-- recurse if index is a parent_indexer
	if getmetatable(self.indx) == Parent_indexer then
		return self.indx:resolve(snippet.parent)
	else
		return snippet.parent.insert_nodes[self.indx]
	end
end

local function P(indx)
	return Parent_indexer:new({ indx = indx })
end

-- TODO(@bew): Categorize each Snippet method, between:
-- - DefinedSnippet (created, not yet added)
-- - RegisteredSnippet (added in collection)
-- - ExpandedSnippet
-- - ..(?)

function Snippet:init_nodes()
	local insert_nodes = {}
	for i, node in ipairs(self.nodes) do
		---(allowed: A BareInternalSnippet will later be a full snippet)
		---@diagnostic disable-next-line: assign-type-mismatch
		node.parent = self
		node.indx = i
		if
			node.type == types.insertNode
			or node.type == types.exitNode
			or node.type == types.snippetNode
			or node.type == types.choiceNode
			or node.type == types.dynamicNode
			or node.type == types.restoreNode
		then
			if node.pos then
				insert_nodes[node.pos] = node
			end
		end
	end

	if insert_nodes[1] then
		insert_nodes[1].prev = self
		for i = 2, #insert_nodes do
			insert_nodes[i].prev = insert_nodes[i - 1]
			insert_nodes[i - 1].next = insert_nodes[i]
		end
		insert_nodes[#insert_nodes].next = self

		self.inner_first = insert_nodes[1]
		self.inner_last = insert_nodes[#insert_nodes]
	else
		self.inner_first = self
		self.inner_last = self
	end

	self.insert_nodes = insert_nodes
end

---@param nodes LuaSnip.Node|LuaSnip.Node[]
---@return LuaSnip.SnippetNode
local function wrap_nodes_in_snippetNode(nodes)
	if getmetatable(nodes) then
		-- is a node, not a table.
		if nodes.type ~= types.snippetNode then
			-- is not a snippetNode.

			-- pos might have been nil, just set it correctly here.
			nodes.pos = 1
			return SN(nil, { nodes })
		else
			-- is a snippetNode, wrapping it twice is unnecessary.
			return nodes ---@type LuaSnip.SnippetNode
		end
	else
		-- is a table of nodes.
		return SN(nil, nodes)
	end
end

---@param opts LuaSnip.Opts.SnippetNode
---@return LuaSnip.NormalizedSnippetNodeOpts
local function init_snippetNode_opts(opts)
	---@type LuaSnip.NormalizedSnippetNodeOpts
	local in_node = {} ---@diagnostic disable-line: missing-fields

	in_node.child_ext_opts =
		ext_util.child_complete(vim.deepcopy(opts.child_ext_opts or {}))

	if opts.merge_child_ext_opts == nil then
		in_node.merge_child_ext_opts = true
	else
		in_node.merge_child_ext_opts = opts.merge_child_ext_opts
	end

	in_node.callbacks = opts.callbacks or {}
	-- return empty table for non-specified callbacks.
	setmetatable(in_node.callbacks, callbacks_mt)

	return in_node
end

local stored_mt = {
	__index = function(table, key)
		-- default-node is just empty text.
		local val = SN(nil, { iNode.I(1) })
		val.is_default = true
		rawset(table, key, val)
		return val
	end,
}

---@param opts LuaSnip.Opts.Snippet
---@return LuaSnip.NormalizedSnippetOpts
local function init_snippet_opts(opts)
	---@type LuaSnip.NormalizedSnippetOpts
	local in_node = {} ---@diagnostic disable-line: missing-fields

	-- The metatable will return `sn(t(""))` for so-far-undefined keys.
	in_node.stored = setmetatable({}, stored_mt)

	-- wrap non-snippetNode in snippetNode.
	for key, nodes in pairs(opts.stored or {}) do
		in_node.stored[key] = wrap_nodes_in_snippetNode(nodes)
	end

	return vim.tbl_extend("error", in_node, init_snippetNode_opts(opts))
end

---@param context LuaSnip.SnipContext
---@param opts LuaSnip.Opts.Snippet
---@return LuaSnip.NormalizedSnippetContext
local function init_snippet_context(context, opts)
	---@type LuaSnip.NormalizedSnippetContext
	local effective_context = {} ---@diagnostic disable-line: missing-fields

	local given_trigger = context.trig
	if not given_trigger then
		error("Snippet trigger is not set!")
	end
	-- note: at this point `given_trigger` is guaranteed to be a string

	-- trig is set by user, trigger is used internally.
	-- not worth a breaking change, we just make it compatible here.
	effective_context.trigger = given_trigger

	effective_context.name = context.name or given_trigger

	-- context.{desc,dscr} could be nil, string or table.
	-- (defaults to trigger)
	effective_context.description =
		util.to_line_table(context.desc or context.dscr or given_trigger)
	-- (keep dscr to avoid breaking downstream usages)
	effective_context.dscr = effective_context.description

	-- might be nil, but whitelisted in snippetProxy.
	effective_context.priority = context.priority

	-- might be nil, but whitelisted in snippetProxy.
	-- shall be a string, allowed values: "snippet", "autosnippet"
	-- stylua: ignore
	assert(
		   context.snippetType == nil
		or context.snippetType == "snippet"
		or context.snippetType == "autosnippet",
		"snippetType has to be either 'snippet' or 'autosnippet' (or unset)"
	)
	-- switch to plural forms so that we can use this for indexing
	-- stylua: ignore
	effective_context.snippetType =
		   context.snippetType == "autosnippet" and "autosnippets"
		or context.snippetType == "snippet"     and "snippets"
		or nil

	-- may be nil.
	effective_context.filetype = context.filetype

	-- maybe do this in a better way when we have more parameters, but this is
	-- fine for now:

	-- not a necessary argument.
	if context.docstring ~= nil then
		effective_context.docstring = util.to_line_table(context.docstring)
	end

	-- can't use `cond and ... or ...` since we have truthy values.
	effective_context.wordTrig =
		util.ternary(context.wordTrig ~= nil, context.wordTrig, true)
	effective_context.hidden =
		util.ternary(context.hidden ~= nil, context.hidden, false)

	effective_context.regTrig =
		util.ternary(context.regTrig ~= nil, context.regTrig, false)

	effective_context.docTrig = context.docTrig
	local engine
	if type(context.trigEngine) == "function" then
		-- if trigEngine is function, just use that.
		engine = context.trigEngine
	else
		-- otherwise, it is nil or string, if it is string, that is the name,
		-- otherwise use "pattern" if regTrig is set, and finally fall back to
		-- "plain" if it is not.
		local engine_name = util.ternary(
			context.trigEngine ~= nil,
			context.trigEngine,
			util.ternary(context.regTrig ~= nil, "pattern", "plain")
		)
		engine = trig_engines[engine_name]
		if not engine then
			error("Unknown trigEngine '" .. engine_name .. "'")
		end
	end
	---@cast engine -nil (We know it's valid here)

	-- make sure to pass through nil-trigEngineOpts, they will be recognized and
	-- we will get a default-version of that function instead of generating a
	-- curried (?) version of it (which would waste space I think).
	effective_context.trig_matcher =
		engine(effective_context.trigger, context.trigEngineOpts)

	effective_context.resolveExpandParams = generate_resolve_expand_params_func(
		context.condition or opts.condition,
		context.resolveExpandParams
	)
	effective_context.show_condition = context.show_condition
		or opts.show_condition
		or true_func

	-- init invalidated here.
	-- This is because invalidated is a key that can be populated without any
	-- information on the actual snippet (it can be used by snippetProxy!) and
	-- it should be also available to the snippet-representations in the
	-- snippet-list, and not in the expanded snippet, as doing this in
	-- `init_snippet_opts` would suggest.
	effective_context.invalidated = false

	return effective_context
end

local function verify_nodes(nodes)
	for i, node in ipairs(nodes) do
		if node.parent then
			error(
				"Node at position "
					.. i
					.. " is already initialized! This is forbidden, generate a new node and pass it instead."
			)
		end
	end
end

-- Create snippet without initializing opts+context.
-- this might be called from snippetProxy.
---@param snip table
---@param nodes LuaSnip.Node|LuaSnip.Node[]
---@param opts? LuaSnip.Opts.Node
---@return LuaSnip.BareInternalSnippet
local function _S(snip, nodes, opts)
	nodes = util.wrap_nodes(nodes)
	-- tbl_extend creates a new table! Important with Proxy, metatable of snip
	-- will be changed later.
	snip = Snippet:new(
		vim.tbl_extend("error", snip, {
			nodes = nodes,
			insert_nodes = {},
			mark = nil,
			dependents = {},
			active = false,
			type = types.snippet,
			-- dependents_dict is responsible for associating
			-- function/dynamicNodes ("dependents") with their argnodes.
			-- There are a few important requirements that have to be
			-- fulfilled:
			-- Allow associating present dependent with non-present argnode
			-- (and vice-versa).
			-- This is required, because a node outside some dynamicNode
			-- could depend on a node inside it, and since the content of a
			-- dynamicNode changes, it is possible that the argnode will be
			-- generated.
			-- As soon as that happens, it should be possible to immediately
			-- find the dependents that depend on the newly-generated argnode,
			-- without searching the snippet.
			--
			-- The dependents_dict enables all of this by storing every node
			-- which is addressable by either `absolute_indexer` or
			-- `key_indexer` (or even directly, just with its own
			-- table, ie. `self`) under its path.
			-- * `absolute_indexer`: the path is the sequence of jump_indices
			-- which leads to this node, for example {1,3,1}.
			-- * `key_indexer`: the path is {"key", <the_key>}.
			-- * `node`: the path is {node}.
			-- With each type of node-reference (absolute_indexer, key, node),
			-- the node which is referenced by it, is stored under path ..
			-- {"node"} (if it exists inside the current snippet!!), while the
			-- dependents are stored at path .. {"dependents"}.
			-- The manner in which the dependents are stored is also
			-- interesting:
			-- They are not stored in eg a list, since we would then have to
			-- deal with explicitly invalidating them (remove them from the
			-- list to prevent its growing too large). No, the dependents are
			-- stored under their own absolute position (not absolute _insert_
			-- position, functionNodes don't have a jump-index, and thus can't
			-- be addressed using absolute insert position), which means that
			--
			-- a) once a dependent is re-generated, for example by a
			-- dynamicNode, it will not take up new space, but simply overwrite
			-- the old one (which is very desirable!!)
			-- b) we will still store some older, unnecessary dependents
			--
			-- (imo) a outweighs b, which is why this design was chosen.
			-- (non-visible nodes are ignored by tracking their visibility in
			-- the snippet separately, it is then queried in eg.
			-- `update_dependents`)
			--
			-- Related functions:
			-- * `dependent:set_dependents` to insert argnode+dependent in
			--   `dependents_dict`, in the according to the above description.
			-- * `set_argnodes` to insert the absolute_insert_position ..
			--   {"node"} into dependents_dict.
			-- * `get_args` to get the text of the argnodes to some dependent
			--   node.
			-- * `update_dependents` can be called to find all dependents, and
			--   update the visible ones.
			dependents_dict = dict.new(),

			-- list of snippets expanded within the region of this snippet.
			-- sorted by their buffer-position, for quick searching.
			child_snippets = {},
		}),
		opts
	)
	---@cast snip LuaSnip.BareInternalSnippet

	-- is propagated to all subsnippets, used to quickly find the outer snippet
	snip.snippet = snip
	-- FIXME(@bew): typing is annoying here, because at this stage we only have
	--   the guarentee that snip is a BareInternalSnippet.
	--   (and we know this function's return might never be a full snippet..)

	verify_nodes(nodes)
	snip:init_nodes()

	if not snip.insert_nodes[0] then
		-- Generate implied i(0)
		local i0 = iNode.I(0)
		local i0_indx = #nodes + 1
		-- FIXME(@bew): same comment as for `snip.snippet`'s typing..
		i0.parent = snip
		i0.indx = i0_indx
		snip.insert_nodes[0] = i0
		snip.nodes[i0_indx] = i0
	end

	return snip
end

---@alias LuaSnip.SnipContext.BuiltinTrigEngine
---| '"plain"' # The default behavior, the trigger has to match the text before the
---    cursor exactly.
---
---| '"pattern"' # The trigger is interpreted as a Lua pattern, and is a match
---    if `trig .. "$"` matches the line up to the cursor.
---    Capture-groups will be accessible as `snippet.captures`.
---
---| '"ecma"' # The trigger is interpreted as an ECMAscript-regex, and is a
---    match if `trig .. "$"` matches the line up to the cursor.
---    Capture-groups will be accessible as `snippet.captures`.
---    This `trigEngine` requires `jsregexp` (see
---    [LSP-snippets-transformations](#transformations)) to be installed, if it
---    is not, this engine will behave like `"plain"`.
---
---| '"vim"' # The trigger is interpreted as a vim-regex, and is a match if
---    `trig .. "$"` matches the line up to the cursor.
---    Capture-groups will be accessible as `snippet.captures`, but there is one
---    caveat: the matching is done using `matchlist`, so for now empty-string
---    submatches will be interpreted as unmatched, and the corresponding
---    `snippet.captures[i]` will be `nil` (this will most likely change, don't
---    rely on this behavior).

---@class LuaSnip.SnipContext.TrigEngineFn.Opts
---@field max_len integer Upper bound on the length of the trigger.
--   If set, the `line_to_cursor` will be truncated (from the cursor of
--   course) to `max_len` characters before performing the match.
--   This is implemented because feeding long `line_to_cursor` into e.g. the
--   pattern-`trigEngine` will hurt performance quite a bit.
--   (see issue Luasnip#1103)
--   This option is implemented for all `trigEngines`.

---@alias LuaSnip.SnipContext.TrigMatcher fun(line_to_cursor: string, trigger: string): [string, string[]]
---@alias LuaSnip.SnipContext.TrigEngineFn fun(trigger: string, opts: LuaSnip.SnipContext.TrigEngineFn.Opts): LuaSnip.SnipContext.TrigMatcher

---@alias LuaSnip.ResolveExpandParamsFn fun(snippet: LuaSnip.Snippet, line_to_cursor: string, matched_trigger: string, captures: string[]): LuaSnip.ExpandParams?

---@class LuaSnip.ExpandParams
---
---@field trigger? string The fully matched trigger.
---@field captures? string[] Updated capture-groups from parameter in snippet
---  expansion.
---  NOTE: Both `trigger` and `captures` can override the values returned via
---  `trigEngine`.
---@field clear_region? {from: [integer, integer], to: [integer, integer]}
---  Both (0, 0)-indexed {<row>, <column>}, the region where text has to be
---  cleared before inserting the snippet.
---@field env_override? {[string]: string[]|string} Override or extend
---  the snippet's environment (`snip.env`)

---@alias LuaSnip.SnipContext.ShowConditionFn fun(line_to_cursor: string): boolean
---@alias LuaSnip.SnipContext.ShowCondition LuaSnip.SnipContext.ShowConditionFn|LuaSnip.SnipContext.ConditionObj
---@alias LuaSnip.SnipContext.ConditionFn fun(line_to_cursor: string, matched_trigger: string, captures: string[]): boolean
---@alias LuaSnip.SnipContext.Condition LuaSnip.SnipContext.ConditionFn|LuaSnip.SnipContext.ConditionObj

---@class LuaSnip.SnipContext
---
---@field trig? string The trigger of the snippet.
---  If the text in front of (to the left of) the cursor when `ls.expand()` is
---  called matches it, the snippet will be expanded.
---  By default, "matches" means the text in front of the cursor matches the
---  trigger exactly, this behavior can be modified through `trigEngine`.
---
---@field name? string Can be used to identify the snippet.
---
---@field desc? string|string[] Description of the snippet.
---
---@field dscr? string|string[] Same as `desc`.
---
---@field wordTrig? boolean If true, the snippet is only expanded if the word
---  (`[%w_]+`) before the cursor matches the trigger entirely.
---  Defaults to true.
---
---@field regTrig? boolean whether the trigger should be interpreted as a
---  Lua pattern. Defaults to false.
---  Consider setting `trigEngine` to `"pattern"` instead, it is more expressive,
---  and in line with other settings.
---
---@field trigEngine? LuaSnip.SnipContext.BuiltinTrigEngine|LuaSnip.SnipContext.TrigEngineFn
---  Determines how `trig` is interpreted, and what it means for it to "match"
---  the text in front of the cursor.
---  This behavior can be completely customized by passing a function, but the
---  predefined ones should suffice in most cases.
---
---@field trigEngineOpts? LuaSnip.SnipContext.TrigEngineFn.Opts Options for the
---  used `trigEngine`.
---
---@field docstring? string|string[] Textual representation of the snippet, specified like
---  `desc`. Overrides docstrings loaded from `json`.
---
---@field docTrig? string used as `line_to_cursor` during docstring-generation.
---  This might be relevant if the snippet relies on specific values in the
---  capture-groups (for example, numbers, which won't work with the default
---  `$CAPTURESN` used during docstring-generation)
---
---@field hidden? boolean Hint for completion-engines.
---  If set, the snippet should not show up when querying snippets.
---
---@field priority? number Priority of the snippet. Defaults to 1000.
---  Snippets with high priority will be matched to a trigger before those with
---  a lower one.
---  The priority for multiple snippets can also be set in `add_snippets`.
---
---@field snippetType? "snippet"|"autosnippet" Decides whether this snippet has
---  to be triggered by `ls.expand()` or whether is triggered automatically.
---  (don't forget to set `ls.config.setup({ enable_autosnippets = true })` if
---  you want to use this feature).
---  If unset, the snippet type will be determined by how the snippet is added.
---
---@field resolveExpandParams? LuaSnip.ResolveExpandParamsFn
---  - `snippet`: The expanding snippet object
---  - `line_to_cursor`: The line up to the cursor.
---  - `matched_trigger`: The fully matched trigger (can be retrieved
---    from `line_to_cursor`, but we already have that info here :D)
---  - `captures`: Captures as returned by `trigEngine`.
---
---  This function will be evaluated in `Snippet:matches()` to decide whether
---  the snippet can be expanded or not.
---  Returns a table if the snippet can be expanded, `nil` if can not.
---
---  If any field in the returned table is `nil`, the default is used (`trigger` and `captures` as
---  returned by `trigEngine`, `clear_region` such that exactly the trigger is
---  deleted, no overridden environment-variables).
---
---  A good example for the usage of `resolveExpandParams` can be found in the
---  implementation of [`postfix`](https://github.com/L3MON4D3/LuaSnip/blob/master/lua/luasnip/extras/postfix.lua).
---
---@field condition? LuaSnip.SnipContext.Condition
---  - `line_to_cursor`: the line up to the cursor.
---  - `matched_trigger`: the fully matched trigger (can be retrieved
---    from `line_to_cursor`, but we already have that info here :D).
---  - `captures`: if the trigger is pattern, contains the capture-groups.
---    Again, could be computed from `line_to_cursor`, but we already did so.
---
---  This function can prevent manual snippet expansion via `ls.expand()`.
---  Return `true` to allow expansion, and `false` to prevent it.
---
---@field show_condition? LuaSnip.SnipContext.ShowCondition
---  This function is (should be) evaluated by completion engines, indicating
---  whether the snippet should be included in current completion candidates.
---  Defaults to a function returning `true`.
---
---  This is different from `condition` because `condition` is evaluated by
---  LuaSnip on snippet expansion (and thus has access to the matched trigger and
---  captures), while `show_condition` is (should be) evaluated by the
---  completion engines when scanning for available snippet candidates.
---
---@field filetype? string The filetype of the snippet.
---  This overrides the filetype the snippet is added (via `add_snippet`) as.

---@class LuaSnip.Opts.Snippet: LuaSnip.Opts.SnippetNode
---@field stored? {[string]: LuaSnip.Node} Snippet-level state for restore node.
---
---@field show_condition? LuaSnip.SnipContext.ShowCondition Same as
---  `show_condition` in snippet context. (here for backward compat)
---@field condition? LuaSnip.SnipContext.Condition Same as `condition` in
---  snippet context. (here for backward compat)

---@param context string|LuaSnip.SnipContext The snippet context.
---  Passing a string is equivalent to passing `{ trig = <the string> }`.
---@param nodes LuaSnip.Node|LuaSnip.Node[] The nodes that make up the snippet.
---@param opts? LuaSnip.Opts.Snippet
---@return LuaSnip.Snippet
local function S(context, nodes, opts)
	opts = opts or {}

	local snip_with_ctx =
		init_snippet_context(node_util.wrap_context(context), opts)
	local snip_with_opts = init_snippet_opts(opts)

	local base_snip = vim.tbl_extend("error", snip_with_ctx, snip_with_opts)
	local snip = _S(base_snip, nodes, opts)
	---@cast snip LuaSnip.Snippet

	if __luasnip_get_loaded_file_frame_debuginfo ~= nil then
		-- this snippet is being lua-loaded, and the source should be recorded.
		snip._source =
			source.from_debuginfo(__luasnip_get_loaded_file_frame_debuginfo())
	end

	return snip
end
extend_decorator.register(
	S,
	{ arg_indx = 1, extend = node_util.snippet_extend_context },
	{ arg_indx = 3 }
)

---@class LuaSnip.SnippetNode: LuaSnip.BareInternalSnippet, LuaSnip.NormalizedSnippetNodeOpts
---@field is_default boolean

---@class LuaSnip.Opts.SnippetNode: LuaSnip.Opts.Node
---@field callbacks? {[integer]: {[LuaSnip.EventType]: fun(node: LuaSnip.Node, event_args?: table)}}
---  Contains functions by node position, that are called upon entering/leaving
---  a node of this snippet.
---  To register a callback for the snippets' own events, the key `[-1]` may
---  be used.
---
---  For example: to print text upon entering the _second_ node of a snippet,
---  `callbacks` should be set as follows:
---  ```lua
---  {
---    -- position of the node, not the jump-index!!
---    -- s("trig", {t"first node", t"second node", i(1, "third node")}).
---    [2] = {
---      [events.enter] = function(node, _event_args) print("2!") end
---    }
---  }
---  ```
---  More info on events in [events](#events).
---
---@field child_ext_opts? `false`|LuaSnip.ChildExtOpts (TODO: doc!)
---@field merge_child_ext_opts? boolean (TODO: doc!)

---@param pos integer?
---@param nodes LuaSnip.Node|LuaSnip.Node[] The nodes that make up the snippet.
---@param opts? LuaSnip.Opts.SnippetNode
---@return LuaSnip.SnippetNode
function SN(pos, nodes, opts)
	opts = opts or {}

	local snip = Snippet:new(
		vim.tbl_extend("error", {
			pos = pos,
			nodes = util.wrap_nodes(nodes),
			insert_nodes = {},
			mark = nil,
			dependents = {},
			active = false,
			type = types.snippetNode,
		}, init_snippetNode_opts(opts)),
		opts
	)
	---@cast snip LuaSnip.SnippetNode

	verify_nodes(nodes)
	snip:init_nodes()

	return snip
end
extend_decorator.register(SN, { arg_indx = 3 })

---@param pos integer?
---@param nodes LuaSnip.Node|LuaSnip.Node[] The nodes that make up the `snippetNode`.
---@param indent_text string Used to indent the nodes inside this `snippetNode`.
---  All occurrences of `"$PARENT_INDENT"` are replaced with the actual indent
---  of the parent.
---@param opts? LuaSnip.Opts.SnippetNode
---@return LuaSnip.SnippetNode
local function ISN(pos, nodes, indent_text, opts)
	local snip = SN(pos, nodes, opts)

	local function get_indent(parent_indent)
		local indentstring = ""
		if vim.bo.expandtab then
			-- preserve content of $PARENT_INDENT, but expand tabs before/after it
			for str in vim.gsplit(indent_text, "$PARENT_INDENT", true) do
				-- append expanded text and parent_indent, we'll remove the superfluous one after the loop.
				indentstring = indentstring
					.. util.expand_tabs(
						{ str },
						util.tab_width(),
						#indentstring + #parent_indent
					)[1]
					.. parent_indent
			end
			indentstring = indentstring:sub(1, -#parent_indent - 1)
		else
			indentstring = indent_text:gsub("$PARENT_INDENT", parent_indent)
		end

		return indentstring
	end

	function snip:indent(parent_indent)
		Snippet.indent(self, get_indent(parent_indent))
	end

	-- expand_tabs also needs to be modified: the children of the isn get the
	-- indent of the isn, so we'll have to calculate it now.
	-- This is done with a dummy-indentstring of the correct length.
	function snip:expand_tabs(tabwidth, indentstrlen)
		Snippet.expand_tabs(
			self,
			tabwidth,
			#get_indent(string.rep(" ", indentstrlen))
		)
	end

	return snip
end
extend_decorator.register(ISN, { arg_indx = 4 })

-- FIXME(@bew): should only be on ExpandedSnippet 🤔
function Snippet:remove_from_jumplist()
	if not self.visible then
		-- snippet not visible => already removed.
		-- Don't remove it twice.
		return
	end

	-- prev is i(-1)(startNode), prev of that is the outer/previous snippet.
	-- pre is $0 or insertNode.
	local pre = self.prev.prev
	-- similar for next, self.next is the i(0).
	-- nxt is snippet.
	local nxt = self.next.next

	-- the advantage of remove_from_jumplist over exit is that the former
	-- modifies its parents child_snippets, or the root-snippet-list.
	-- Since the owners of this snippets' child_snippets are invalid anyway, we
	-- don't bother modifying them.
	self:exit()

	local sibling_list = self.parent_node ~= nil
			and self.parent_node.parent.snippet.child_snippets
		or session.snippet_roots[vim.api.nvim_get_current_buf()]
	local self_indx
	for i, snip in ipairs(sibling_list) do
		if snip == self then
			self_indx = i
		end
	end
	table.remove(sibling_list, self_indx)

	-- previous snippet jumps to this one => redirect to jump to next one.
	if pre then
		if pre.inner_first == self then
			if pre == nxt then
				pre.inner_first = nil
			else
				pre.inner_first = nxt
			end
		elseif pre.next == self then
			pre.next = nxt
		end
	end
	if nxt then
		if nxt.inner_last == self.next then
			if pre == nxt then
				nxt.inner_last = nil
			else
				nxt.inner_last = pre
			end
		-- careful here!! nxt.prev is its start_node, nxt.prev.prev is this
		-- snippet.
		elseif nxt.prev.prev == self.next then
			nxt.prev.prev = pre
		end
	end
end

-- FIXME(@bew): should only be on ExpandedSnippet 🤔
function Snippet:insert_into_jumplist(
	current_node,
	parent_node,
	sibling_snippets,
	own_indx
)
	-- this is always the case.
	local start_node = self.prev

	local prev_snippet = sibling_snippets[own_indx - 1]
	-- have not yet inserted self!!
	local next_snippet = sibling_snippets[own_indx]

	-- can set this immediately
	-- parent_node is nil if the snippet is toplevel.
	self.parent_node = parent_node

	-- only consider sibling-snippets with the same parent-node as
	-- previous/next snippet for linking-purposes.
	-- They are siblings because they are expanded in the same snippet, not
	-- because they have the same parent_node.
	local prev, next
	if prev_snippet ~= nil and prev_snippet.parent_node == parent_node then
		prev = prev_snippet
	end
	if next_snippet ~= nil and next_snippet.parent_node == parent_node then
		next = next_snippet
	end

	-- whether roots should be linked together.
	local link_roots = session.config.link_roots

	-- whether children of the same snippet should be linked to their parent
	-- and eachother.
	local link_children = session.config.link_children

	if parent_node then
		if node_util.linkable_node(parent_node) then
			-- snippetNode (which has to be empty to be viable here) and
			-- insertNode can both deal with inserting a snippet inside them
			-- (ie. hooking it up st. it can be visited after jumping back to
			-- the snippet of parent).
			-- in all cases
			if link_children and prev ~= nil then
				-- if we have a previous snippet we can link to, just do that.
				prev.next.next = self
				start_node.prev = prev.insert_nodes[0]
			else
				-- only jump from parent to child if link_children is set.
				if link_children then
					-- prev is nil, but we can link up using the parent.
					parent_node.inner_first = self
				end
				-- make sure we can jump back to the parent.
				start_node.prev = parent_node
			end

			-- exact same reasoning here as in prev-case above, omitting comments.
			if link_children and next ~= nil then
				-- jump from next snippets start_node to $0.
				next.prev.prev = self.insert_nodes[0]
				-- jump from $0 to next snippet (skip its start_node)
				self.insert_nodes[0].next = next
			else
				if link_children then
					parent_node.inner_last = self.insert_nodes[0]
				end
				self.insert_nodes[0].next = parent_node
			end
		else
			-- naively, even if the parent is linkable, there might be snippets
			-- before/after that share the same parent, so we could
			-- theoretically link up with them.
			-- This, however, can cause cyclic jumps, for example if the
			-- previous child-snippet contains the current node: we will jump
			-- from the end of the new snippet into the previous child-snippet,
			-- and from its last node into the new snippet.
			-- Since cycles should be avoided (very weird if the jumps just go
			-- in a circle), we have no choice but to fall back to this
			-- old-style linkage.

			-- Don't jump from current_node to this snippet (I feel
			-- like that should be good: one can still get back to ones
			-- previous history, and we don't mess up whatever jumps
			-- are set up around current_node)
			start_node.prev = current_node
			self.insert_nodes[0].next = current_node
		end
	-- don't link different root-nodes for unlinked_roots.
	elseif link_roots then
		-- inserted into top-level snippet-forest, just hook up with prev, next.
		-- prev and next have to be snippets or nil, in this case.
		if prev ~= nil then
			prev.next.next = self
			start_node.prev = prev.insert_nodes[0]
		end
		if next ~= nil then
			self.insert_nodes[0].next = next
			next.prev.prev = self.insert_nodes[0]
		end
	end

	table.insert(sibling_snippets, own_indx, self)
end

-- IDEA(THINKING, @bew): Most methods in Snippet should really be on a BareInternalSnippet class
-- But this method should be on an actual Snippet class
-- (so it can be called on a full Snippet, but not a BareInternalSnippet)
-- This came to my mind because this function uses `self.stored` &
-- `self.merge_child_ext_opts` that _only_ exist on full Snippet but not on
-- BareInternalSnippet.
function Snippet:trigger_expand(current_node, pos_id, env, indent_nodes)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, session.ns_id, pos_id, {})

	local pre_expand_res = self:event(
		events.pre_expand,
		{ expand_pos = pos, expand_pos_mark_id = pos_id }
	) or {}

	-- update pos, event-callback might have moved the extmark.
	pos = vim.api.nvim_buf_get_extmark_by_id(0, session.ns_id, pos_id, {})

	-- find tree-node the snippet should be inserted at (could be before another node).
	local _, sibling_snippets, own_indx, parent_node =
		node_util.snippettree_find_undamaged_node(pos, {
			tree_respect_rgravs = false,
			tree_preference = node_util.binarysearch_preference.outside,
			snippet_mode = "linkable",
		})
	local n_siblings_pre = #sibling_snippets

	if current_node then
		if parent_node then
			if node_util.linkable_node(parent_node) then
				node_util.refocus(current_node, parent_node)
				parent_node:input_enter_children()
			else
				-- enter extmarks of parent_node, but don't enter it
				-- "logically", it will not be the parent of the snippet.
				parent_node:focus()
				-- enter current node, it will contain the new snippet.
				current_node:input_enter_children()
			end
		else
			-- if no parent_node, completely leave.
			node_util.refocus(current_node, nil)

			-- in this branch, it may happen that the snippet we leave is
			-- invalid and removed from the snippet-list during `refocus`.
			-- This is not catastrophic, but we have to recognize it here, and
			-- update the `own_indx` among the snippet-roots (one was deleted,
			-- the computed index is no longer valid since there may have been
			-- a shift down over `own_indx`)
			if n_siblings_pre ~= #sibling_snippets then
				-- only own_indx can change, since the text in the buffer is
				-- unchanged, while the number of roots is.
				_, _, own_indx, _ =
					node_util.snippettree_find_undamaged_node(pos, {
						tree_respect_rgravs = false,
						tree_preference = node_util.binarysearch_preference.outside,
						snippet_mode = "linkable",
					})
			end
		end

		-- There may be other snippets inside of this parent_node/on this level
		-- of the snippet-tree whose extmarks have to be adjusted s.t. they
		-- don't contain the text that will be inserted during put_initial.
		-- Node's/snippet's extmarks that are outside of this parent_node/not
		-- siblings of this node will be adjusted during the refocus above, if
		-- applicable.
		--
		-- The following adjustments may do too much, but there's no issue
		-- with that, and we're on the safe side.

		-- set rgrav false for snippets/nodes where the right boundary
		-- coincides with the position we insert at now...
		for i = 1, own_indx - 1 do
			sibling_snippets[i]:subtree_set_pos_rgrav(pos, -1, false)
		end
		-- set rgrav true for snippets/nodes where the left boundary
		-- coincides with the position we insert at now...
		for i = own_indx, #sibling_snippets do
			sibling_snippets[i]:subtree_set_pos_rgrav(pos, 1, true)
		end
	end

	Environ:override(env, pre_expand_res.env_override or {})

	if indent_nodes then
		local indentstring = util.line_chars_before(pos):match("^%s*")
		-- expand tabs before indenting to keep indentstring unmodified
		if vim.bo.expandtab then
			self:expand_tabs(util.tab_width(), #indentstring)
		end
		self:indent(indentstring)
	end

	-- (possibly) keep user-set opts.
	if self.merge_child_ext_opts then
		self.effective_child_ext_opts = ext_util.child_extend(
			vim.deepcopy(self.child_ext_opts),
			session.config.ext_opts
		)
	else
		self.effective_child_ext_opts = vim.deepcopy(self.child_ext_opts)
	end

	local parent_ext_base_prio
	-- if inside another snippet, increase priority accordingly.
	-- parent_node is only set if this snippet is expanded inside another one.
	if parent_node then
		parent_ext_base_prio = parent_node.parent.ext_opts.base_prio
	else
		parent_ext_base_prio = session.config.ext_base_prio
	end

	-- own highlight comes from self.child_ext_opts.snippet.
	self:resolve_node_ext_opts(
		parent_ext_base_prio,
		self.effective_child_ext_opts[self.type]
	)

	self.env = env
	self:subsnip_init()

	self:init_positions({})
	self:init_insert_positions({})

	self:make_args_absolute()

	self:set_dependents()
	self:set_argnodes(self.dependents_dict)

	-- at this point `stored` contains the snippetNodes that will actually
	-- be used, indent them once here.
	for _, node in pairs(self.stored) do
		node:indent(self.indentstr)
	end

	local start_node = iNode.I(0)
	start_node.pos = -1
	-- needed for querying node-path from snippet to this node.
	start_node.absolute_position = { -1 }
	start_node.parent = self
	start_node.visible = true

	-- hook up i0 and start_node, and then the snippet itself.
	-- they are outside, not inside the snippet.
	-- This should clearly be the case for start_node, but also for $0 since
	-- jumping to $0 should make/mark the snippet non-active (for example via
	-- extmarks)
	start_node.next = self
	self.prev = start_node
	self.insert_nodes[0].prev = self
	self.next = self.insert_nodes[0]

	self:put(pos)

	self:update()
	self:update_dependents({ children = true })

	self:insert_into_jumplist(
		current_node,
		parent_node,
		sibling_snippets,
		own_indx
	)

	return parent_node
end

-- returns copy of snip if it matches, nil if not.
-- fallback_match can be used to proceed even if the text before the cursor does
-- not match the snippets' trigger. This is useful for completion engines, where
-- the text does usually not match, but resolveExpandParams may still give
-- useful data (e.g. when the snippet is a treesitter_postfix, see
-- https://github.com/L3MON4D3/LuaSnip/issues/1374)
--
-- IDEA(THINKING, @bew): Similar to `trigger_expand`, this uses fields from
-- Snippet (from its context & opts) not BareInternalSnippet, should be moved.
---@param line_to_cursor string
---@param opts? {fallback_match?: string}
---@return LuaSnip.ExpandParams?
function Snippet:matches(line_to_cursor, opts)
	local fallback_match = util.default_tbl_get(nil, opts, "fallback_match")

	local match, captures = self.trig_matcher(line_to_cursor, self.trigger)

	if not match and fallback_match ~= nil then
		match = fallback_match
		captures = {}
	end

	-- Trigger or regex didn't match.
	if not match then
		return nil
	end

	local expand_params =
		self:resolveExpandParams(line_to_cursor, match, captures)
	if not expand_params then
		return nil
	end

	local from = #line_to_cursor - #match + 1

	-- if wordTrig is set, the char before the trigger can't be \w or the
	-- word has to start at the beginning of the line.
	if
		self.wordTrig
		and not (
			from == 1
			or string.match(
					string.sub(line_to_cursor, from - 1, from - 1),
					"[%w_]"
				)
				== nil
		)
	then
		return nil
	end

	return expand_params
end

---@generic T
---@param self T
---@return T
function Snippet:copy()
	return util.copy3(self)
end

function Snippet:del_marks()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, session.ns_id, node.mark.id)
	end
end

function Snippet:is_interactive(info)
	for _, node in ipairs(self.nodes) do
		-- return true if any node depends on another node or is an insertNode.
		if node:is_interactive(info) then
			return true
		end
	end
	return false
end

function Snippet:dump()
	for i, node in ipairs(self.nodes) do
		print(i)
		print(node.mark.opts.right_gravity, node.mark.opts.end_right_gravity)
		local from, to = node.mark:pos_begin_end()
		print(from[1], from[2])
		print(to[1], to[2])
	end
end

function Snippet:put_initial(pos)
	for _, node in ipairs(self.nodes) do
		-- save pos to compare to later.
		local old_pos = vim.deepcopy(pos)
		node:put_initial(pos)

		-- correctly set extmark for node.
		-- does not modify ext_opts[node.type].
		local mark_opts = vim.tbl_extend("keep", {
			right_gravity = false,
			end_right_gravity = false,
		}, node:get_passive_ext_opts())
		node.mark = mark(old_pos, pos, mark_opts)
	end
	self.visible = true
end

-- populate env,inden,captures,trigger(regex),... but don't put any text.
-- the env may be passed in opts via opts.env, if none is passed a new one is
-- generated.
--
-- IDEA(THINKING, @bew): Similar to `trigger_expand`, this uses fields from
-- Snippet (from its context & opts) not BareInternalSnippet, should be moved.
function Snippet:fake_expand(opts)
	if not opts then
		opts = {}
	end
	-- set eg. env.TM_SELECTED_TEXT to $TM_SELECTED_TEXT
	if opts.env then
		self.env = opts.env
	else
		self.env = Environ.fake()
	end

	self.captures = {}
	setmetatable(self.captures, {
		__index = function(_, key)
			return "$CAPTURE" .. tostring(key)
		end,
	})
	if self.docTrig then
		-- use docTrig as entire line up to cursor, this assumes that it
		-- actually matches the trigger.
		local _
		_, self.captures = self.trig_matcher(self.docTrig, self.trigger)
		self.trigger = self.docTrig
	else
		self.trigger = "$TRIGGER"
	end
	self.ext_opts = vim.deepcopy(session.config.ext_opts)

	self:indent("")

	self.___static_expanded = true

	-- ext_opts don't matter here, just use convenient values.
	self.effective_child_ext_opts = self.child_ext_opts
	self.ext_opts = self.node_ext_opts

	self:subsnip_init()

	self:init_positions({})
	self:init_insert_positions({})

	self:make_args_absolute()

	self:set_dependents()
	self:set_argnodes(self.dependents_dict)

	self:static_init()

	-- no need for update_dependents_static, update_static alone will cause updates for all child-nodes.
	self:update_static()
end

-- to work correctly, this may require that the snippets' env,indent,captures? are
-- set.
---@return string[]?
function Snippet:get_static_text()
	if self.static_text then
		return self.static_text
		-- copy+fake_expand the snippet here instead of in whatever code needs to know the docstring.
	elseif not self.ext_opts then
		-- not a snippetNode and not yet initialized
		local snipcop = self:copy()
		-- sets env, captures, etc.
		snipcop:fake_expand()
		local static_text = snipcop:get_static_text()
		self.static_text = static_text
		return static_text
	end

	if not self.static_visible then
		return nil
	end
	local text = { "" }
	for _, node in ipairs(self.nodes) do
		local node_text = node:get_static_text()
		-- append first line to last line of text so far.
		text[#text] = text[#text] .. node_text[1]
		for i = 2, #node_text do
			text[#text + 1] = node_text[i]
		end
	end
	-- cache computed text, may be called multiple times for
	-- function/dynamicNodes.
	self.static_text = text
	return text
end

---@return string[]
function Snippet:get_docstring()
	if self.docstring then
		return self.docstring
		-- copy+fake_expand the snippet here instead of in whatever code needs to know the docstring.
	elseif not self.ext_opts then
		-- not a snippetNode and not yet initialized
		local snipcop = self:copy()
		-- sets env, captures, etc.
		snipcop:fake_expand()
		local docstring = snipcop:get_docstring()
		self.docstring = docstring
		return docstring
	end
	local docstring = { "" }
	for _, node in ipairs(self.nodes) do
		local node_text = node:get_docstring()
		-- append first line to last line of text so far.
		docstring[#docstring] = docstring[#docstring] .. node_text[1]
		for i = 2, #node_text do
			docstring[#docstring + 1] = node_text[i]
		end
	end
	-- cache computed text, may be called multiple times for
	-- function/dynamicNodes.
	-- if not outer snippet, wrap it in ${}.
	self.docstring = self.type == types.snippet and docstring
		or util.string_wrap(docstring, self.pos)
	return self.docstring
end

function Snippet:update()
	for _, node in ipairs(self.nodes) do
		node:update()
	end
end

function Snippet:update_static()
	for _, node in ipairs(self.nodes) do
		node:update_static()
	end
end

function Snippet:update_restore()
	for _, node in ipairs(self.nodes) do
		node:update_restore()
	end
end

function Snippet:store()
	for _, node in ipairs(self.nodes) do
		node:store()
	end
end

function Snippet:indent(prefix)
	self.indentstr = prefix
	for _, node in ipairs(self.nodes) do
		node:indent(prefix)
	end
end

function Snippet:expand_tabs(tabwidth, indenstringlen)
	for _, node in ipairs(self.nodes) do
		node:expand_tabs(tabwidth, indenstringlen)
	end
end

function Snippet:subsnip_init()
	node_util.subsnip_init_children(self, self.nodes)
end

Snippet.init_positions = node_util.init_child_positions_func(
	"absolute_position",
	"nodes",
	"init_positions"
)
Snippet.init_insert_positions = node_util.init_child_positions_func(
	"absolute_insert_position",
	"insert_nodes",
	"init_insert_positions"
)

function Snippet:make_args_absolute()
	for _, node in ipairs(self.nodes) do
		---(allowed: this arg only exists for some node types)
		---@diagnostic disable-next-line: redundant-parameter
		node:make_args_absolute(self.absolute_insert_position)
	end
end

function Snippet:input_enter(_, dry_run)
	if dry_run then
		dry_run.active[self] = true
		return
	end

	self.visited = true
	self.active = true

	if self.type == types.snippet then
		-- set snippet-passive -> visited/unvisited for all children.
		self:set_ext_opts("passive")
	end
	self.mark:update_opts(self.ext_opts.active)

	self:event(events.enter)
end

function Snippet:input_leave(_, dry_run)
	if dry_run then
		dry_run.active[self] = false
		return
	end

	self:event(events.leave)

	-- set own ext_opts to snippet-passive, there is no passive for snippets.
	self.mark:update_opts(self.ext_opts.snippet_passive)
	if self.type == types.snippet then
		-- also override all nodes' ext_opt.
		self:set_ext_opts("snippet_passive")
	end

	self.active = false
end

function Snippet:set_ext_opts(opt_name)
	for _, node in ipairs(self.nodes) do
		node:set_ext_opts(opt_name)
	end
end

function Snippet:jump_into(dir, no_move, dry_run)
	self:init_dry_run_active(dry_run)

	-- if dry_run, ignore self.active
	if self:is_active(dry_run) then
		self:input_leave(no_move, dry_run)

		if dir == 1 then
			return self.next:jump_into(dir, no_move, dry_run)
		else
			return self.prev:jump_into(dir, no_move, dry_run)
		end
	else
		self:input_enter(no_move, dry_run)

		if dir == 1 then
			return self.inner_first:jump_into(dir, no_move, dry_run)
		else
			return self.inner_last:jump_into(dir, no_move, dry_run)
		end
	end
end

-- Snippets inherit Node:jump_from, it shouldn't occur normally, but may be
-- used in LSP-Placeholders.

function Snippet:exit()
	if self.type == types.snippet then
		-- insertNode also call exit for their child_snippets, but if we
		-- :exit() the whole snippet we can just remove all of them here.
		for _, snip in ipairs(self.child_snippets) do
			snip:exit()
		end
		self.child_snippets = {}
	end

	self.visible = false
	for _, node in ipairs(self.nodes) do
		node:exit()
	end
	self.mark:clear()
	self.active = false
end

function Snippet:text_only()
	for _, node in ipairs(self.nodes) do
		if node.type ~= types.textNode then
			return false
		end
	end
	return true
end

--- Trigger event with args
---@param event LuaSnip.EventType
---@param event_args? table
---@return any
-- FIXME(@bew): This should only be on SnippetNode & Snippet 🤔
--   (to access callbacks)
function Snippet:event(event, event_args)
	-- there are 3 sources of a callback, for a snippetNode:
	-- self.callbacks[-1], self.node_callbacks, and parent.callbacks[self.pos].
	local m1_cb, cb, parent_cb
	-- since we handle pre-expand callbacks here, we need to handle the
	-- event_res, which may be returned by more than one callback.
	-- In order to keep it simple, we just return any non-nil result.
	local m1_cb_res, cb_res, parent_cb_res

	m1_cb = self.callbacks[-1][event]
	if m1_cb then
		m1_cb_res = m1_cb(self, event_args)
	end

	cb = self.node_callbacks[event]
	if cb then
		cb_res = cb(self, event_args)
	end

	if self.type == types.snippetNode and self.pos then
		-- if snippetNode, also do callback for position in parent.
		parent_cb = self.parent.callbacks[self.pos][event]
		if parent_cb then
			parent_cb_res = parent_cb(self)
		end
	end

	session.event_node = self
	session.event_args = event_args
	vim.api.nvim_exec_autocmds("User", {
		pattern = "Luasnip" .. events.to_string(self.type, event),
		modeline = false,
	})

	return vim.F.if_nil(cb_res, m1_cb_res, parent_cb_res)
end

local function nodes_from_pattern(pattern)
	local nodes = {}
	local text_active = true
	local iNode_indx = 1
	local tokens = pattern_tokenizer.tokenize(pattern)
	for _, text in ipairs(tokens) do
		if text_active then
			nodes[#nodes + 1] = tNode.T(text)
		else
			nodes[#nodes + 1] = iNode.I(iNode_indx, text)
			iNode_indx = iNode_indx + 1
		end
		text_active = not text_active
	end
	-- This is done so the user ends up at the end of the snippet either way
	-- and may use their regular expand-key to expand the snippet.
	-- Autoexpanding doesn't quite work, if the snippet ends with an
	-- interactive part and the user overrides whatever is put in there, the
	-- jump to the i(0) may trigger an expansion, and the helper-snippet could
	-- not easily be removed, as the snippet the user wants to actually use is
	-- inside of it.
	-- Because of that it is easier to let the user do the actual expanding,
	-- but help them on the way to it (by providing an easy way to override the
	-- "interactive" parts of the pattern-trigger).
	--
	-- if even number of nodes, the last is an insertNode (nodes begins with
	-- textNode and alternates between the two).
	if #nodes % 2 == 0 then
		nodes[#nodes] = iNode.I(0, tokens[#tokens])
	else
		nodes[#nodes + 1] = iNode.I(0)
	end
	return nodes
end

-- only call on actual snippets, snippetNodes don't have trigger.
function Snippet:get_pattern_expand_helper()
	if not self.expand_helper_snippet then
		local nodes = nodes_from_pattern(self.trigger)
		self.expand_helper_snippet = S(self.trigger, nodes, {
			callbacks = {
				[0] = {
					[events.enter] = function(_)
						vim.schedule(function()
							-- Remove this helper snippet as soon as the i(0)
							-- is reached.
							require("luasnip").unlink_current()
						end)
					end,
				},
			},
		})
	end
	-- will be copied in actual expand.
	return self.expand_helper_snippet
end

function Snippet:find_node(predicate, opts)
	for _, node in ipairs(self.nodes) do
		if predicate(node) then
			return node
		else
			local node_in_child = node:find_node(predicate, opts)
			if node_in_child then
				return node_in_child
			end
		end
	end
	if predicate(self.prev) then
		return self.prev
	end
	return nil
end

function Snippet:insert_to_node_absolute(position)
	if #position == 0 then
		return self.absolute_position
	end
	local insert_indx = util.pop_front(position)
	return self.insert_nodes[insert_indx]:insert_to_node_absolute(position)
end

function Snippet:set_dependents()
	for _, node in ipairs(self.nodes) do
		node:set_dependents()
	end
end

function Snippet:set_argnodes(dict)
	node_mod.Node.set_argnodes(self, dict)
	for _, node in ipairs(self.nodes) do
		node:set_argnodes(dict)
	end
end

function Snippet:resolve_position(position)
	-- only snippets have -1-node.
	if position == -1 and self.type == types.snippet then
		return self.prev
	end

	return self.nodes[position]
end

function Snippet:static_init()
	node_mod.Node.static_init(self)
	for _, node in ipairs(self.nodes) do
		node:static_init()
	end
end

-- called only for snippetNodes!
-- => FIXME(@bew): should then be in a SnippetNode class?
function Snippet:resolve_child_ext_opts()
	if self.merge_child_ext_opts then
		self.effective_child_ext_opts = ext_util.child_extend(
			vim.deepcopy(self.child_ext_opts),
			self.parent.effective_child_ext_opts
		)
	else
		self.effective_child_ext_opts = vim.deepcopy(self.child_ext_opts)
	end
end

local function no_match()
	return nil
end

function Snippet:invalidate()
	self.hidden = true
	-- override matching-function.
	self.matches = no_match
	self.invalidated = true
	snippet_collection.invalidated_count = snippet_collection.invalidated_count
		+ 1
end

-- used in add_snippets to get variants of snippet.
function Snippet:retrieve_all()
	return { self }
end

function Snippet:get_keyed_node(key)
	-- get key-node from dependents_dict.
	return self.dependents_dict:get({ "key", key, "node" })
end

-- adjust rgrav of nodes left (direction=-1) or right (direction=1) of node at
-- child_indx.
-- (direction is the direction into which is searched, from child_indx outward)
-- assumption: direction-endpoint of node is on child_endpoint. (caller
-- responsible)
function Snippet:set_sibling_rgravs(node, child_endpoint, direction, rgrav)
	node_util.nodelist_adjust_rgravs(
		self.nodes,
		node.absolute_position[#node.absolute_position] + direction,
		child_endpoint,
		direction,
		rgrav,
		true
	)
end

-- called only if the "-direction"-endpoint has to be changed, but the
-- "direction"-endpoint not.
function Snippet:subtree_set_pos_rgrav(pos, direction, rgrav)
	self.mark:set_rgrav(-direction, rgrav)

	local child_from_indx
	if direction == 1 then
		child_from_indx = 1
	else
		child_from_indx = #self.nodes
	end

	node_util.nodelist_adjust_rgravs(
		self.nodes,
		child_from_indx,
		pos,
		direction,
		rgrav,
		true
	)
end
-- changes rgrav of all nodes and all endpoints in this snippetNode to `rgrav`.
function Snippet:subtree_set_rgrav(rgrav)
	self.mark:set_rgravs(rgrav, rgrav)
	for _, node in ipairs(self.nodes) do
		node:subtree_set_rgrav(rgrav)
	end
end

-- for this to always return a node if pos is withing the snippet-boundaries,
-- the snippet must have valid extmarks.
-- Looks for a node that has a specific property (either linkable, or
-- interactive), which can be indicated by setting mode to either of the two
-- (as string).
function Snippet:node_at(pos, mode)
	if #self.nodes == 0 then
		-- special case: no children (can naturally occur with dynamicNode,
		-- when its function could not be evaluated, or if a user passed an empty snippetNode).
		return self
	end

	-- collect nodes where pos is either in gravity-adjusted boundaries, ..
	local gravity_matches = {}
	-- .. or just inside the regular boundaries.
	-- Both are needed, so we can fall back to matches if there is no gravity_match
	-- with the desired mode ("linkable" or "interactive"), fall back to
	-- extmark_matches if there is also no regular match with the desired mode,
	-- and finally fall back to any match (still preferring extmark-match) if
	-- there is no match with the desired mode at all.
	-- Unfortunately, all this is necessary, since there are many cases where
	-- we may return no linkable node, despite there apparently being one in
	-- reach of the cursor.
	local matches = {}
	-- find_node visits all nodes in-order until the predicate returns true.
	self:find_node(function(node)
		if not node:leaf() then
			-- not a leaf-node.
			return false
		end

		local node_mark = node.mark
		local node_from, node_to = node_mark:pos_begin_end_raw()
		-- if pos certainly beyond node, quickly continue.
		-- This means a little more work for the nodes in range of pos, while
		-- all nodes well before it are quickly skipped => should benefit
		-- all cases where the runtime of this is noticeable, and which are not
		-- unrealistic (lots of zero-width nodes).
		if util.pos_cmp(pos, { node_to[1], node_to[2] + 1 }) > 0 then
			return false
		end

		-- generate gravity-adjusted endpoints.
		local grav_adjusted_from = { node_from[1], node_from[2] }
		local grav_adjusted_to = { node_to[1], node_to[2] }
		if node_mark:get_rgrav(-1) then
			grav_adjusted_from[2] = grav_adjusted_from[2] + 1
		end
		if node_mark:get_rgrav(1) then
			grav_adjusted_to[2] = grav_adjusted_to[2] + 1
		end

		local cmp_pos_to = util.pos_cmp(pos, node_to)
		local cmp_pos_from = util.pos_cmp(pos, node_from)
		local cmp_grav_from = util.pos_cmp(pos, grav_adjusted_from)
		local cmp_grav_to = util.pos_cmp(pos, grav_adjusted_to)

		if cmp_pos_from < 0 then
			-- abort once the first node is definitely beyond pos.
			-- (extmark-gravity can't move column to the left).
			return true
		end

		-- pos between from,to <=> from <= pos < to is used when choosing which
		-- extmark to insert text into, so we should adopt it here.
		if cmp_grav_from >= 0 and cmp_grav_to < 0 then
			table.insert(gravity_matches, node)
		end
		-- matches does not have to respect the extmark-conventions, just catch
		-- all possible nodes.
		if cmp_pos_from >= 0 and cmp_pos_to <= 0 then
			table.insert(matches, node)
		end
	end)

	-- instead of stupid nesting ifs, and because we can't use goto since
	-- non-luajit-users should also be able to run luasnip :(((
	return (function()
		for _, node in ipairs(gravity_matches) do
			if node[mode](node) then
				return node
			end
		end
		for _, node in ipairs(matches) do
			if node[mode](node) then
				return node
			end
		end
		-- no interactive node found, fall back to any match.
		return gravity_matches[1] or matches[1]
	end)()
end

-- return the node the snippet jumps to, or nil if there isn't one.
function Snippet:next_node()
	-- self.next is $0, .next is either the surrounding node, or the next
	-- snippet in the list, .prev is the i(-1) if the self.next.next is the
	-- next snippet.

	if self.parent_node and self.next.next == self.parent_node then
		return self.next.next
	else
		return (self.next.next and self.next.next.prev)
	end
end

function Snippet:extmarks_valid()
	-- assumption: extmarks are contiguous, and all can be queried via pos_begin_end_raw.
	local ok, current_from, self_to =
		pcall(self.mark.pos_begin_end_raw, self.mark)
	if not ok then
		return false
	end

	-- the following code assumes that the snippet(Node) has at least one child,
	-- if it doesn't, it's valid anyway.
	if #self.nodes == 0 then
		return true
	end

	for _, node in ipairs(self.nodes) do
		local ok_, node_from, node_to =
			pcall(node.mark.pos_begin_end_raw, node.mark)
		-- this snippet is invalid if:
		-- - we can't get the position of some node
		-- - the positions aren't contiguous, don't completely fill the parent, or the `to` is before the `from`, or
		-- - any child of this node violates these rules.
		if
			not ok_
			or util.pos_cmp(current_from, node_from) ~= 0
			or util.pos_cmp(node_from, node_to) > 0
			or not node:extmarks_valid()
		then
			return false
		end
		current_from = node_to
	end
	if util.pos_cmp(current_from, self_to) ~= 0 then
		return false
	end

	return true
end

function Snippet:subtree_do(opts)
	opts.pre(self)
	for _, child in ipairs(self.nodes) do
		child:subtree_do(opts)
	end
	opts.post(self)
end

function Snippet:get_snippet()
	if self.type == types.snippet then
		return self
	else
		return self.parent.snippet
	end
end

-- affect all children nested into this snippet.
function Snippet:subtree_leave_entered()
	if self.active then
		for _, node in ipairs(self.nodes) do
			node:subtree_leave_entered()
		end
		self:input_leave()
	else
		if self.type ~= types.snippetNode then
			-- the exit-nodes (-1 and 0) may be active if the snippet itself is
			-- not; just do these two calls, no hurt if they're not active.
			self.prev:subtree_leave_entered()
			self.insert_nodes[0]:subtree_leave_entered()
		end
	end
end

function Snippet:put(pos)
	--- Put text-content of snippet into buffer and set marks.
	local old_pos = vim.deepcopy(pos)
	self:put_initial(pos)

	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, self:get_passive_ext_opts())
	self.mark = mark(old_pos, pos, mark_opts)

	-- The start_nodes' marks should stay at the beginning of the snippet, only
	-- the first mark is needed.
	self.prev.mark = self.nodes[1].mark
end

return {
	Snippet = Snippet,
	S = S,
	_S = _S,
	SN = SN,
	P = P,
	ISN = ISN,
	wrap_nodes_in_snippetNode = wrap_nodes_in_snippetNode,
	init_snippet_context = init_snippet_context,
	init_snippet_opts = init_snippet_opts,
}
