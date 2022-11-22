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

	opts = opts or {}

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

	opts = opts or {}

	in_node.condition = opts.condition or true_func

	in_node.show_condition = opts.show_condition or true_func

	-- return sn(t("")) for so-far-undefined keys.
	in_node.stored = setmetatable(opts.stored or {}, stored_mt)

	-- wrap non-snippetNode in snippetNode.
	for key, nodes in pairs(in_node.stored) do
		in_node.stored[key] = wrap_nodes_in_snippetNode(nodes)
	end

	-- init invalidated here.
	-- This is because invalidated is a key that can be populated without any
	-- information on the actual snippet (it can be used by snippetProxy!).
	in_node.invalidated = false

	return vim.tbl_extend("error", in_node, init_snippetNode_opts(opts))
end

local function init_snippet_context(context)
	if type(context) == "string" then
		context = { trig = context }
	end

	-- trig is set by user, trigger is used internally.
	-- maybe breaking change, but not worth it, probably.
	context.trigger = context.trig
	context.trig = nil

	context.name = context.name or context.trigger

	-- context.dscr could be nil, string or table.
	context.dscr = util.to_line_table(context.dscr or context.trigger)

	-- might be nil, but whitelisted in snippetProxy.
	context.priority = context.priority

	-- might be nil, but whitelisted in snippetProxy.
	-- shall be a string, allowed values: "snippet", "autosnippet"
	assert(
		not context.snippetType
			or context.snippetType == "snippet"
			or context.snippetType == "autosnippet",
		"snippetType has to be either 'snippet' or 'autosnippet' (or unset)"
	)
	-- switch to plural forms so that we can use this for indexing
	context.snippetType = context.snippetType == "autosnippet"
			and "autosnippets"
		or context.snippetType == "snippet" and "snippets"
		or nil

	-- maybe do this in a better way when we have more parameters, but this is
	-- fine for now.

	-- not a necessary argument.
	if context.docstring then
		context.docstring = util.to_line_table(context.docstring)
	end

	-- default: true.
	if context.wordTrig == nil then
		context.wordTrig = true
	end

	-- default: false.
	if context.hidden == nil then
		context.hidden = false
	end

	-- default: false.
	if context.regTrig == nil then
		context.regTrig = false
	end

	return context
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
	local snip = init_snippet_context(context)
	snip = vim.tbl_extend("error", snip, init_snippet_opts(opts))

	return _S(snip, nodes, opts)
end
extend_decorator.register(
	S,
	{ arg_indx = 1, extend = node_util.snippet_extend_context },
	{ arg_indx = 3 }
)

function SN(pos, nodes, opts)
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

	-- update() may insert text, set marks appropriately.
	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = true,
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
	local from
	local match
	local captures = {}
	if self.regTrig then
		-- capture entire trigger, must be put into match.
		local find_res = { string.find(line_to_cursor, self.trigger .. "$") }
		if #find_res > 0 then
			from = find_res[1]
			match = line_to_cursor:sub(from, #line_to_cursor)
			for i = 3, #find_res do
				captures[i - 2] = find_res[i]
			end
		end
	else
		if
			line_to_cursor:sub(
				#line_to_cursor - #self.trigger + 1,
				#line_to_cursor
			) == self.trigger
		then
			from = #line_to_cursor - #self.trigger + 1
			match = self.trigger
		end
	end

	-- Trigger or regex didn't match.
	if not match then
		return nil
	end

	if not self.condition(line_to_cursor, match, captures) then
		return nil
	end

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

function Snippet:enter_node(node_id)
	if self.parent then
		self.parent:enter_node(self.indx)
	end

	for i = 1, node_id - 1 do
		self.nodes[i]:set_mark_rgrav(false, false)
	end

	local node = self.nodes[node_id]
	node:set_mark_rgrav(
		node.ext_gravities_active[1],
		node.ext_gravities_active[2]
	)

	local _, node_to = node.mark:pos_begin_end_raw()
	local i = node_id + 1
	while i <= #self.nodes do
		local other = self.nodes[i]
		local other_from, other_to = other.mark:pos_begin_end_raw()

		local end_equal = util.pos_equal(other_to, node_to)
		other:set_mark_rgrav(util.pos_equal(other_from, node_to), end_equal)
		i = i + 1

		-- As soon as one end-mark wasn't equal, we no longer have to check as the
		-- marks don't overlap.
		if not end_equal then
			break
		end
	end
	while i <= #self.nodes do
		self.nodes[i]:set_mark_rgrav(false, false)
		i = i + 1
	end
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

function Snippet:set_text(node, text)
	local node_from, node_to = node.mark:pos_begin_end_raw()

	self:enter_node(node.indx)
	local ok = pcall(
		vim.api.nvim_buf_set_text,
		0,
		node_from[1],
		node_from[2],
		node_to[1],
		node_to[2],
		text
	)
	-- we can assume that (part of) the snippet was deleted; remove it from
	-- the jumplist.
	if not ok then
		error("[LuaSnip Failed]: " .. vim.inspect(text))
	end
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
		-- This fills captures[1] with docTrig if no capture groups are defined
		-- and therefore slightly differs from normal expansion where it won't
		-- be filled, but that's alright.
		self.captures = { self.docTrig:match(self.trigger) }
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

function Snippet:input_enter()
	self.visited = true
	self.active = true

	if self.type == types.snippet then
		-- set snippet-passive -> visited/unvisited for all children.
		self:set_ext_opts("passive")
	end
	self.mark:update_opts(self.ext_opts.active)

	self:event(events.enter)
end

function Snippet:input_leave()
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

function Snippet:jump_into(dir, no_move)
	if self.active then
		self:input_leave()
		if dir == 1 then
			return self.next:jump_into(dir, no_move)
		else
			return self.prev:jump_into(dir, no_move)
		end
	else
		self:input_enter()
		if dir == 1 then
			return self.inner_first:jump_into(dir, no_move)
		else
			return self.inner_last:jump_into(dir, no_move)
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

function Snippet:set_mark_rgrav(val_begin, val_end)
	-- set own markers.
	node_mod.Node.set_mark_rgrav(self, val_begin, val_end)

	local snip_pos_begin, snip_pos_end = self.mark:pos_begin_end_raw()

	if
		snip_pos_begin[1] == snip_pos_end[1]
		and snip_pos_begin[2] == snip_pos_end[2]
	then
		for _, node in ipairs(self.nodes) do
			node:set_mark_rgrav(val_begin, val_end)
		end
		return
	end

	local node_indx = 1
	-- the first node starts at begin-mark.
	local node_on_begin_mark = true

	-- only change gravities on nodes that absolutely have to.
	while node_on_begin_mark do
		-- will be set later if the next node has to be updated as well.
		node_on_begin_mark = false
		local node = self.nodes[node_indx]
		if not node then
			break
		end
		local node_pos_begin, node_pos_end = node.mark:pos_begin_end_raw()
		-- use false, false as default, this is what most nodes will be set to.
		local new_rgrav_begin, new_rgrav_end =
			node.mark.opts.right_gravity, node.mark.opts.end_right_gravity
		if
			node_pos_begin[1] == snip_pos_begin[1]
			and node_pos_begin[2] == snip_pos_begin[2]
		then
			new_rgrav_begin = val_begin

			if
				node_pos_end[1] == snip_pos_begin[1]
				and node_pos_end[2] == snip_pos_begin[2]
			then
				new_rgrav_end = val_begin
				-- both marks of this node were on the beginning of the snippet
				-- so this has to be checked again for the next node.
				node_on_begin_mark = true
				node_indx = node_indx + 1
			end
		end
		node:set_mark_rgrav(new_rgrav_begin, new_rgrav_end)
	end

	-- the first node starts at begin-mark.
	local node_on_end_mark = true

	node_indx = #self.nodes
	while node_on_end_mark do
		local node = self.nodes[node_indx]
		if not node then
			break
		end
		local node_pos_begin, node_pos_end = node.mark:pos_begin_end_raw()
		-- will be set later if the next node has to be updated as well.
		node_on_end_mark = false
		-- use false, false as default, this is what most nodes will be set to.
		local new_rgrav_begin, new_rgrav_end =
			node.mark.opts.right_gravity, node.mark.opts.end_right_gravity
		if
			node_pos_end[1] == snip_pos_end[1]
			and node_pos_end[2] == snip_pos_end[2]
		then
			new_rgrav_end = val_end

			if
				node_pos_begin[1] == snip_pos_end[1]
				and node_pos_begin[2] == snip_pos_end[2]
			then
				new_rgrav_begin = val_end
				-- both marks of this node were on the end-mark of the snippet
				-- so this has to be checked again for the next node.
				node_on_end_mark = true
				node_indx = node_indx - 1
			end
		end
		node:set_mark_rgrav(new_rgrav_begin, new_rgrav_end)
	end
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
	vim.cmd(
		"doautocmd <nomodeline> User Luasnip"
			.. events.to_string(self.type, event)
	)

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
