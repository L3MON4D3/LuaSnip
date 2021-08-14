local node_mod = require("luasnip.nodes.node")
local iNode = require("luasnip.nodes.insertNode")
local t = require("luasnip.nodes.textNode").T
local util = require("luasnip.util.util")
local types = require("luasnip.util.types")
local mark = require("luasnip.util.mark").mark
local conf = require("luasnip.config")

Luasnip_ns_id = vim.api.nvim_create_namespace("Luasnip")

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

local function wrap_nodes(nodes)
	-- safe to assume, if nodes has a metatable, it is a single node, not a
	-- table.
	if getmetatable(nodes) then
		return { nodes }
	else
		return nodes
	end
end

local function S(context, nodes, condition, ...)
	if not condition then
		condition = function()
			return true
		end
	end

	if type(context) == "string" then
		context = { trig = context }
	end

	-- context.dscr could be nil, string or table.
	context.dscr = util.wrap_value(context.dscr or context.trig)

	-- split entries at \n.
	local dscr = {}
	for _, str in ipairs(context.dscr) do
		local split = vim.split(str, "\n", true)
		for i = 1, #split do
			dscr[#dscr + 1] = split[i]
		end
	end

	-- default: true.
	if context.wordTrig == nil then
		context.wordTrig = true
	end

	nodes = wrap_nodes(nodes)
	local snip = Snippet:new({
		trigger = context.trig,
		dscr = dscr,
		name = context.name or context.trig,
		wordTrig = context.wordTrig,
		regTrig = context.regTrig,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = { ... },
		mark = nil,
		dependents = {},
		active = false,
		env = {},
		type = types.snippet,
	})

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

local function SN(pos, nodes)
	local snip = Snippet:new({
		pos = pos,
		nodes = wrap_nodes(nodes),
		insert_nodes = {},
		current_insert = 0,
		mark = nil,
		dependents = {},
		active = false,
		type = types.snippetNode,
	})
	snip:init_nodes()
	return snip
end

local function ISN(pos, nodes, indent_text)
	local snip = Snippet:new({
		pos = pos,
		nodes = wrap_nodes(nodes),
		insert_nodes = {},
		current_insert = 0,
		mark = nil,
		dependents = {},
		active = false,
		type = types.snippetNode,
	})
	function snip:indent(parent_indent)
		Snippet.indent(self, indent_text:gsub("$PARENT_INDENT", parent_indent))
	end
	snip:init_nodes()
	return snip
end

local function PSN(pos, nodes, prefix)
	local snip = Snippet:new({
		pos = pos,
		nodes = wrap_nodes(nodes),
		insert_nodes = {},
		current_insert = 0,
		mark = nil,
		dependents = {},
		active = false,
		type = types.snippetNode,
	})
	function snip:indent(parent_indent)
		Snippet.indent(self, parent_indent .. prefix)
	end

	-- insert prefix as first node of snippetNode.
	for i = #snip.nodes, 1, -1 do
		snip.nodes[i + 1] = snip.nodes[i]
	end
	snip.nodes[1] = t({ prefix })
	snip:init_nodes()
	return snip
end

local function pop_env(env)
	local cur = util.get_cursor_0ind()
	env.TM_CURRENT_LINE = vim.api.nvim_buf_get_lines(
		0,
		cur[1],
		cur[1] + 1,
		false
	)[1]
	env.TM_CURRENT_WORD = util.word_under_cursor(cur, env.TM_CURRENT_LINE)
	env.TM_LINE_INDEX = tostring(cur[1])
	env.TM_LINE_NUMBER = tostring(cur[1] + 1)
	env.TM_FILENAME = vim.fn.expand("%:t")
	env.TM_FILENAME_BASE = vim.fn.expand("%:t:s?\\.[^\\.]\\+$??")
	env.TM_DIRECTORY = vim.fn.expand("%:p:h")
	env.TM_FILEPATH = vim.fn.expand("%:p")

	env.SELECT_RAW, env.SELECT_DEDENT, env.TM_SELECTED_TEXT =
		util.get_selection()
end

function Snippet:remove_from_jumplist()
	-- Snippet is 'surrounded' by insertNodes.
	local pre = self.prev.prev
	local nxt = self.next.next

	-- Only existing Snippet.
	if not pre and not nxt then
		vim.api.nvim_buf_clear_namespace(0, Luasnip_ns_id, 0, -1)
		Luasnip_active_choice = nil
		Luasnip_current_nodes[vim.api.nvim_get_current_buf()] = nil
	end

	if pre then
		-- Snippet is linearly behind previous snip.
		if pre.pos == 0 then
			pre.next = nxt
		else
			-- check if self is only snippet inside insert node.
			if nxt ~= pre then
				pre.inner_first = nxt.next
			else
				pre.inner_first = nil
				pre.inner_last = nil
				return
			end
		end
	end
	if nxt then
		-- linearly before?
		if nxt.pos == -1 then
			nxt.prev = pre
		else
			-- case 'only snippet inside iNode' is handled above.
			nxt.inner_last = pre
		end
	end
end

local function insert_into_jumplist(snippet, start_node, current_node)
	if current_node then
		if current_node.pos == 0 then
			if current_node.next then
				-- next is beginning of another snippet.
				if current_node.next.pos == -1 then
					current_node.next.prev = snippet.insert_nodes[0]
					-- next is outer insertNode.
				else
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

	snippet.next = snippet.insert_nodes[0]
	snippet.prev = start_node

	snippet.insert_nodes[0].prev = snippet
	start_node.next = snippet
end

function Snippet:trigger_expand(current_node)
	self:indent(util.get_current_line_to_cursor():match("^%s*"))

	-- keep (possibly) user-set opts.
	if not self.ext_opts then
		-- if expanded outside another snippet use configs' ext_opts, if inside,
		-- use those of that snippet and increase priority.
		-- for now do a check for .indx, TODO: maybe only expand in insertNodes.
		if current_node and (current_node.indx and current_node.indx > 1) then
			self.ext_opts = util.increase_ext_prio(
				vim.deepcopy(current_node.parent.ext_opts),
				conf.config.ext_prio_increase
			)
		else
			self.ext_opts = vim.deepcopy(conf.config.ext_opts)
		end
	end
	pop_env(self.env)

	-- remove snippet-trigger, Cursor at start of future snippet text.
	util.remove_n_before_cur(#self.trigger)

	local start_node = iNode.I(0)

	local pos = util.get_cursor_0ind()
	local old_pos = vim.deepcopy(pos)

	self:put_initial(pos)

	local mark_opts = vim.tbl_extend("keep", {
		right_gravity = false,
		end_right_gravity = false,
	}, self.ext_opts[types.snippet].passive)
	self.mark = mark(old_pos, pos, mark_opts)
	self:set_old_text()

	self:update()

	-- Marks should stay at the beginning of the snippet, only the first mark is needed.
	start_node.mark = self.nodes[1].mark
	start_node.pos = -1
	start_node.parent = self

	insert_into_jumplist(self, start_node, current_node)

	if current_node and current_node.pos > 0 then
		current_node.inner_active = true
	end
	self:jump_into(1)
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

	if not self.condition(unpack(self.user_args)) then
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

	local cp = self:copy()
	cp.trigger = match
	cp.captures = captures
	return cp
end

function Snippet:enter_node(node_id)
	if self.parent then
		self.parent:enter_node(self.indx)
	end

	local node = self.nodes[node_id]
	local node_to = util.get_ext_position_end(node.mark.id)
	for i = 1, node_id - 1 do
		-- print(string.format("%d: %s, %s", i, "<", "<"))
		self.nodes[i]:set_mark_rgrav(false, false)
	end
	-- print(vim.inspect(node_from), vim.inspect(node_to))
	-- print(string.format("[crt] %d: %s, %s", node_id,
	-- 	node.ext_gravities_active[1] and ">" or "<",
	-- 	node.ext_gravities_active[2] and ">" or "<"))
	node:set_mark_rgrav(
		node.ext_gravities_active[1],
		node.ext_gravities_active[2]
	)
	for i = node_id + 1, #self.nodes do
		local other = self.nodes[i]
		local other_from, other_to = util.get_ext_positions(other.mark.id)

		-- print(vim.inspect(other_from), vim.inspect(other_to))
		-- print(string.format("%d: %s, %s", i,
		-- 	util.pos_equal(other_from, node_to) and ">" or "<",
		-- 	util.pos_equal(other_to, node_to) and ">" or "<"))

		other:set_mark_rgrav(
			util.pos_equal(other_from, node_to),
			util.pos_equal(other_to, node_to)
		)
	end
	-- print("\n ")
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
	local ok, msg = pcall(
		vim.api.nvim_buf_set_text,
		0,
		node_from[1],
		node_from[2],
		node_to[1],
		node_to[2],
		text
	)
	if not ok then
		-- get correct column-indices:
		node_from = util.bytecol_to_utfcol(node_from)
		node_to = util.bytecol_to_utfcol(node_to)
		print(
			"[LuaSnip Failed]:",
			node_from[1],
			node_from[2],
			node_to[1],
			node_to[2],
			vim.inspect(text)
		)
	end
end

function Snippet:del_marks()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.mark.id)
	end
end

function Snippet:is_interactive()
	for _, node in ipairs(self.nodes) do
		-- return true if any node depends on another node or is an insertNode.
		if
			node.type == types.insertNode
			or ((node.type == types.functionNode or node.type == types.dynamicNode) and #node.args ~= 0)
			or node.type == types.choiceNode
		then
			return true
			-- node is snippet, recurse.
		elseif node.type == types.snippetNode then
			return node:is_interactive()
		end
	end
	return false
end

function Snippet:dump()
	for i, node in ipairs(self.nodes) do
		print(i)
		print(node.mark.opts.right_gravity, node.mark.opts.end_right_gravity)
		local from, to = util.get_ext_positions(node.mark.id)
		print(from[1], from[2])
		print(to[1], to[2])
	end
end

function Snippet:put_initial(pos)
	-- i needed for functions.
	for _, node in ipairs(self.nodes) do
		-- save pos to compare to later.
		local old_pos = vim.deepcopy(pos)

		-- set for snippetNodes.
		if node.type == types.snippetNode then
			node:indent(self.indentstr)
			node.env = self.env
			node.ext_opts = util.increase_ext_prio(
				vim.deepcopy(self.ext_opts),
				conf.config.ext_prio_increase
			)
		end

		node:put_initial(pos)

		-- correctly set extmark for node.
		-- does not modify ext_opts[node.type].
		local mark_opts = vim.tbl_extend("keep", {
			right_gravity = false,
			end_right_gravity = false,
		}, self.ext_opts[node.type].passive)
		node.mark = mark(old_pos, pos, mark_opts)
		node:set_old_text()
	end

	for _, node in ipairs(self.nodes) do
		if
			node.type == types.functionNode or node.type
				== types.dynamicNode
		then
			self:populate_args(node)
		end
	end
end

function Snippet:update()
	for _, node in ipairs(self.nodes) do
		node:update()
	end
end

function Snippet:indent(prefix)
	self.indentstr = prefix
	-- Check once here instead of inside loop.
	if vim.o.expandtab then
		local tab_string = string.rep(
			" ",
			vim.o.shiftwidth ~= 0 and vim.o.shiftwidth or vim.o.tabstop
		)
		for _, node in ipairs(self.nodes) do
			-- put prefix behind newlines.
			if node:has_static_text() then
				for i = 2, #node:get_static_text() do
					-- Note: prefix is not changed but copied.
					node:get_static_text()[i] = prefix
						.. string.gsub(
							node:get_static_text()[i],
							"\t",
							tab_string
						)
				end
			end
		end
	else
		for _, node in ipairs(self.nodes) do
			-- put prefix behind newlines.
			if node:has_static_text() then
				for i = 2, #node:get_static_text() do
					node:get_static_text()[i] = prefix
						.. node:get_static_text()[i]
				end
			end
		end
	end
end

function Snippet:input_enter()
	self.active = true
	self.mark:update_opts(self.ext_opts[self.type].active)
end

function Snippet:input_leave()
	self:update_dependents()
	self.active = false
	self.mark:update_opts(self.ext_opts[self.type].passive)
end

function Snippet:jump_into(dir)
	if self.active then
		self:input_leave()
		if dir == 1 then
			self.next:jump_into(dir)
		else
			self.prev:jump_into(dir)
		end
	else
		self:input_enter()
		if dir == 1 then
			self.inner_first:jump_into(dir)
		else
			self.inner_last:jump_into(dir)
		end
	end
end

-- Snippets inherit Node:jump_from, it shouldn't occur normally, but may be
-- used in LSP-Placeholders.

function Snippet:exit()
	for _, node in ipairs(self.nodes) do
		node:exit()
	end
end

function Snippet:set_mark_rgrav(val_begin, val_end)
	-- set own markers.
	node_mod.Node.set_mark_rgrav(self, val_begin, val_end)

	for _, node in ipairs(self.nodes) do
		node:set_mark_rgrav(val_begin, val_end)
	end
end

function Snippet:populate_args(node)
	for i, arg in ipairs(node.args) do
		local argnode = nil
		-- simple index; references node in this snippet.
		if type(arg) == "number" then
			argnode = self.insert_nodes[arg]
			--parent_indexer: references node outside this snippet, resolve it.
		else
			if getmetatable(arg) == Parent_indexer then
				argnode = arg:resolve(self)
			end
		end
		if argnode then
			node.args[i] = argnode
			argnode.dependents[#argnode.dependents + 1] = node
		end
	end
end

return {
	Snippet = Snippet,
	S = S,
	SN = SN,
	P = P,
	ISN = ISN,
	PSN = PSN,
}
