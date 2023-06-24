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
local callbacks_mt = {
	__index = function(table, key)
		rawset(table, key, {})
		return {}
	end,
}

-- declare SN here, is needed in metatable.
local SN

local stored_mt = {
	__index = function(table, key)
		-- default-node is just empty text.
		local val = SN(nil, { iNode.I(1) })
		val.is_default = true
		rawset(table, key, val)
		return val
	end,
}

local Snippet = node_mod.Node:new()

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

function Snippet:init_nodes()
	local insert_nodes = {}
	for i, node in ipairs(self.nodes) do
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

		node.update_dependents = function(node)
			node:_update_dependents()
			node.parent:update_dependents()
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
			return nodes
		end
	else
		-- is a table of nodes.
		return SN(nil, nodes)
	end
end

local function init_snippetNode_opts(opts)
	local in_node = {}

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

local function init_snippet_opts(opts)
	local in_node = {}

	-- return sn(t("")) for so-far-undefined keys.
	in_node.stored = setmetatable(opts.stored or {}, stored_mt)

	-- wrap non-snippetNode in snippetNode.
	for key, nodes in pairs(in_node.stored) do
		in_node.stored[key] = wrap_nodes_in_snippetNode(nodes)
	end

	return vim.tbl_extend("error", in_node, init_snippetNode_opts(opts))
end

-- context, opts non-nil tables.
local function init_snippet_context(context, opts)
	local effective_context = {}

	-- trig is set by user, trigger is used internally.
	-- not worth a breaking change, we just make it compatible here.
	effective_context.trigger = context.trig

	effective_context.name = context.name or context.trig

	-- context.dscr could be nil, string or table.
	effective_context.dscr = util.to_line_table(context.dscr or context.trig)

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
	end
	effective_context.trig_matcher = engine(effective_context.trigger)

	effective_context.condition = context.condition
		or opts.condition
		or true_func
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

-- Create snippet without initializing opts+context.
-- this might be called from snippetProxy.
local function _S(snip, nodes, opts)
	nodes = util.wrap_nodes(nodes)
	-- tbl_extend creates a new table! Important with Proxy, metatable of snip
	-- will be changed later.
	snip = Snippet:new(
		vim.tbl_extend("error", snip, {
			nodes = nodes,
			insert_nodes = {},
			current_insert = 0,
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
		}),
		opts
	)

	-- is propagated to all subsnippets, used to quickly find the outer snippet
	snip.snippet = snip

	-- the snippet may not have dependents.
	snip._update_dependents = function() end
	snip.update_dependents = snip._update_dependents

	snip:init_nodes()

	if not snip.insert_nodes[0] then
		-- Generate implied i(0)
		local i0 = iNode.I(0)
		local i0_indx = #nodes + 1
		i0.parent = snip
		i0.indx = i0_indx
		snip.insert_nodes[0] = i0
		snip.nodes[i0_indx] = i0
	end

	return snip
end

local function S(context, nodes, opts)
	opts = opts or {}

	local snip = init_snippet_context(node_util.wrap_context(context), opts)
	snip = vim.tbl_extend("error", snip, init_snippet_opts(opts))

	snip = _S(snip, nodes, opts)

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

function SN(pos, nodes, opts)
	opts = opts or {}

	local snip = Snippet:new(
		vim.tbl_extend("error", {
			pos = pos,
			nodes = util.wrap_nodes(nodes),
			insert_nodes = {},
			current_insert = 0,
			mark = nil,
			dependents = {},
			active = false,
			type = types.snippetNode,
		}, init_snippetNode_opts(opts)),
		opts
	)
	snip:init_nodes()

	return snip
end
extend_decorator.register(SN, { arg_indx = 3 })

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

function Snippet:remove_from_jumplist()
	-- prev is i(-1)(startNode), prev of that is the outer/previous snippet.
	local pre = self.prev.prev
	-- similar for next, self.next is the i(0).
	local nxt = self.next.next

	self:exit()

	-- basically four possibilities: only snippet, between two snippets,
	-- inside an insertNode (start), inside an insertNode (end).
	if pre then
		-- Snippet is linearly behind previous snip, the appropriate value
		-- for nxt.prev is set later.
		if pre.pos == 0 then
			pre.next = nxt
		else
			if nxt ~= pre then
				-- if not the only snippet inside the insertNode:
				pre.inner_first = nxt
				nxt.prev = pre
				return
			else
				pre.inner_first = nil
				pre.inner_last = nil
				pre.inner_active = false
				return
			end
		end
	end
	if nxt then
		if nxt.pos == -1 then
			nxt.prev = pre
		else
			-- only possible if this is the last inside an insertNode, only
			-- snippet in insertNode is handled above
			nxt.inner_last = pre
			pre.next = nxt
		end
	end
end

local function insert_into_jumplist(snippet, start_node, current_node)
	if current_node then
		-- currently at the endpoint (i(0)) of another snippet, this snippet
		-- is inserted _behind_ that snippet.
		if current_node.pos == 0 then
			if current_node.next then
				if current_node.next.pos == -1 then
					-- next is beginning of another snippet, this snippet is
					-- inserted before that one.
					current_node.next.prev = snippet.insert_nodes[0]
				else
					-- next is outer insertNode.
					current_node.next.inner_last = snippet.insert_nodes[0]
				end
			end
			snippet.insert_nodes[0].next = current_node.next
			current_node.next = start_node
			start_node.prev = current_node
		elseif current_node.pos == -1 then
			if current_node.prev then
				if current_node.prev.pos == 0 then
					current_node.prev.next = start_node
				else
					current_node.prev.inner_first = snippet
				end
			end
			snippet.insert_nodes[0].next = current_node
			start_node.prev = current_node.prev
			current_node.prev = snippet.insert_nodes[0]
		else
			snippet.insert_nodes[0].next = current_node
			-- jump into snippet directly.
			current_node.inner_first = snippet
			current_node.inner_last = snippet.insert_nodes[0]
			start_node.prev = current_node
		end
	end

	-- snippet is between i(-1)(startNode) and i(0).
	snippet.next = snippet.insert_nodes[0]
	snippet.prev = start_node

	snippet.insert_nodes[0].prev = snippet
	start_node.next = snippet
end

function Snippet:trigger_expand(current_node, pos_id, env)
	local pos = vim.api.nvim_buf_get_extmark_by_id(0, session.ns_id, pos_id, {})
	local pre_expand_res = self:event(events.pre_expand, { expand_pos = pos })
		or {}
	-- update pos, event-callback might have moved the extmark.
	pos = vim.api.nvim_buf_get_extmark_by_id(0, session.ns_id, pos_id, {})

	Environ:override(env, pre_expand_res.env_override or {})

	local indentstring = util.line_chars_before(pos):match("^%s*")
	-- expand tabs before indenting to keep indentstring unmodified
	if vim.bo.expandtab then
		self:expand_tabs(util.tab_width(), #indentstring)
	end
	self:indent(indentstring)

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
	-- for now do a check for .indx.
	if current_node and (current_node.indx and current_node.indx > 1) then
		parent_ext_base_prio = current_node.parent.ext_opts.base_prio
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

	local old_pos = vim.deepcopy(pos)
	self:put_initial(pos)

	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, self:get_passive_ext_opts())
	self.mark = mark(old_pos, pos, mark_opts)

	self:update()
	self:update_all_dependents()

	-- Marks should stay at the beginning of the snippet, only the first mark is needed.
	start_node.mark = self.nodes[1].mark
	start_node.pos = -1
	start_node.parent = self

	insert_into_jumplist(self, start_node, current_node)
end

-- returns copy of snip if it matches, nil if not.
function Snippet:matches(line_to_cursor)
	local match, captures = self.trig_matcher(line_to_cursor, self.trigger)

	-- Trigger or regex didn't match.
	if not match then
		return nil
	end

	if not self.condition(line_to_cursor, match, captures) then
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

	return { trigger = match, captures = captures }
end

-- https://gist.github.com/tylerneylon/81333721109155b2d244
local function copy3(obj, seen)
	-- Handle non-tables and previously-seen tables.
	if type(obj) ~= "table" then
		return obj
	end
	if seen and seen[obj] then
		return seen[obj]
	end

	-- New table; mark it as seen an copy recursively.
	local s = seen or {}
	local res = {}
	s[obj] = res
	for k, v in next, obj do
		res[copy3(k, s)] = copy3(v, s)
	end
	return setmetatable(res, getmetatable(obj))
end

function Snippet:copy()
	return copy3(self)
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
		or util.string_wrap(docstring, rawget(self, "pos"))
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
	self:update_dependents()

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

function Snippet:event(event, event_args)
	local callback = self.callbacks[-1][event]
	local cb_res
	if callback then
		cb_res = callback(self, event_args)
	end
	if self.type == types.snippetNode and self.pos then
		-- if snippetNode, also do callback for position in parent.
		callback = self.parent.callbacks[self.pos][event]
		if callback then
			callback(self)
		end
	end

	session.event_node = self
	session.event_args = event_args
	vim.api.nvim_exec_autocmds("User", {
		pattern = "Luasnip" .. events.to_string(self.type, event),
		modeline = false,
	})

	return cb_res
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

function Snippet:find_node(predicate)
	for _, node in ipairs(self.nodes) do
		if predicate(node) then
			return node
		else
			local node_in_child = node:find_node(predicate)
			if node_in_child then
				return node_in_child
			end
		end
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

function Snippet:update_all_dependents()
	-- call the version that only updates this node.
	self:_update_dependents()
	-- only for insertnodes, others will not have dependents.
	for _, node in ipairs(self.insert_nodes) do
		node:update_all_dependents()
	end
end
function Snippet:update_all_dependents_static()
	-- call the version that only updates this node.
	self:_update_dependents_static()
	-- only for insertnodes, others will not have dependents.
	for _, node in ipairs(self.insert_nodes) do
		node:update_all_dependents_static()
	end
end

function Snippet:resolve_position(position)
	return self.nodes[position]
end

function Snippet:static_init()
	node_mod.Node.static_init(self)
	for _, node in ipairs(self.nodes) do
		node:static_init()
	end
end

-- called only for snippetNodes!
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

-- assumption: direction-endpoint of node at child_from_indx is on child_endpoint.
-- (caller responsible)
local function adjust_children_rgravs(
	self,
	child_endpoint,
	child_from_indx,
	direction,
	rgrav
)
	local i = child_from_indx
	local node = self.nodes[i]
	while node do
		local direction_node_endpoint = node.mark:get_endpoint(direction)
		if util.pos_equal(direction_node_endpoint, child_endpoint) then
			-- both endpoints of node are on top of child_endpoint (we wouldn't
			-- be in the loop with `node` if the -direction-endpoint didn't
			-- match), so update rgravs of the entire subtree to match rgrav
			node:subtree_set_rgrav(rgrav)
		else
			-- only the -direction-endpoint matches child_endpoint, adjust its
			-- position and break the loop (don't need to look at any other
			-- siblings).
			node:subtree_set_pos_rgrav(child_endpoint, direction, rgrav)
			break
		end

		i = i + direction
		node = self.nodes[i]
	end
end

-- adjust rgrav of nodes left (direction=-1) or right (direction=1) of node at
-- child_indx.
-- (direction is the direction into which is searched, from child_indx outward)
function Snippet:set_sibling_rgravs(
	child_endpoint,
	child_indx,
	direction,
	rgrav
)
	adjust_children_rgravs(
		self,
		child_endpoint,
		child_indx + direction,
		direction,
		rgrav
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
	adjust_children_rgravs(self, pos, child_from_indx, direction, rgrav)
end
-- changes rgrav of all nodes and all endpoints in this snippetNode to `rgrav`.
function Snippet:subtree_set_rgrav(rgrav)
	self.mark:set_rgravs(rgrav, rgrav)
	for _, node in ipairs(self.nodes) do
		node:subtree_set_rgrav(rgrav)
	end
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
