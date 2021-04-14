local node_mod = require'luasnip.nodes.node'
local iNode = require'luasnip.nodes.insertNode'
local util = require'luasnip.util.util'

Luasnip_ns_id = vim.api.nvim_create_namespace("Luasnip")

local Snippet = node_mod.Node:new()

function Snippet:init_nodes()
	local insert_nodes = {}
	for i, node in ipairs(self.nodes) do
		node.parent = self
		node.indx = i
		if node.type == 1 or node.type == 4 or node.type == 5 then
			insert_nodes[node.pos] = node
		end
		if node.type == 3 then
			insert_nodes[node.pos] = node
			node.env = self.env
		end
	end

	if insert_nodes[1] then
		insert_nodes[1].prev = self
		for i=2, #insert_nodes do
			insert_nodes[i].prev = insert_nodes[i-1]
			insert_nodes[i-1].next = insert_nodes[i]
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

local function S(context, nodes, condition, ...)
	if not condition then
		condition = function() return true end
	end
	if type(context) == 'string' then
		error("Pass table containing a 'trig'-key and optionally 'dscr' and 'name' as first arg.")
	end
	local snip = Snippet:new{
		trigger = context.trig,
		dscr = context.dscr or context.trig,
		name = context.name or context.trig,
		wordTrig = context.wordTrig,
		regTrig = context.regTrig,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = {...},
		markers = {},
		dependents = {},
		active = false,
		env = {}
	}
	snip:init_nodes()
	return snip
end

local function SN(pos, nodes, condition, ...)
	if not condition then
		condition = function() return true end
	end
	local snip = Snippet:new{
		pos = pos,
		nodes = nodes,
		insert_nodes = {},
		current_insert = 0,
		condition = condition,
		user_args = {...},
		markers = {},
		dependents = {},
		active = false,
		type = 3
	}
	snip:init_nodes()
	return snip
end

local function pop_env(env)
	local cur = util.get_cursor_0ind()
	env.TM_CURRENT_LINE = vim.api.nvim_buf_get_lines(0, cur[1], cur[1]+1, false)[1]
	env.TM_CURRENT_WORD = util.word_under_cursor(cur, env.TM_CURRENT_LINE)
	env.TM_LINE_INDEX = cur[1]
	env.TM_LINE_NUMBER = cur[1]+1
	env.TM_FILENAME = vim.fn.expand("%:t")
	env.TM_FILENAME_BASE = vim.fn.expand("%:t:s?\\.[^\\.]\\+$??")
	env.TM_DIRECTORY = vim.fn.expand("%:p:h")
	env.TM_FILEPATH = vim.fn.expand("%:p")
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
					current_node.prev.next = snippet.insert_nodes[0]
				else
					current_node.prev.inner_first = start_node
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
	self:indent(util.get_current_line_to_cursor())

	pop_env(self.env)

	-- remove snippet-trigger, Cursor at start of future snippet text.
	util.remove_n_before_cur(#self.trigger)

	local start_node = iNode.I(0)

	self:put_initial()
	self:update()

	-- Marks should stay at the beginning of the snippet, only the first mark is needed.
	start_node.markers = self.nodes[1].markers

	insert_into_jumplist(self, start_node, current_node)

	if current_node then
		current_node.inner_active = true
	end
	self:jump_into(1)
end

-- returns copy of snip if it matches, nil if not.
function Snippet:matches(line)
		local from
		local match
		local captures = {}
		if self.regTrig then
			-- capture entire trigger, must be put into match.
			local find_res = {string.find(line, "("..self.trigger..")$")}
			if find_res then
				from = find_res[1]
				match = find_res[3]
				for i = 4, #find_res do
					captures[i-3] = find_res[i]
				end
			end
		else
			if string.sub(line, #line - #self.trigger + 1, #line) == self.trigger then
				from = #line - #self.trigger + 1
				match = self.trigger
			end
		end

		-- Trigger or regex didn't match.
		if not match then
			return nil
		end
		local trigger = self.trigger
		-- Regex-snippets can access matchstring in condition.
		self.trigger = match

		if not self.condition(unpack(self.user_args)) then
			return nil
		end

		-- if wordTrig is set, the char before the trigger has to be \w or the
		-- word has to start at the beginning of the line.
		if self.wordTrig and not (from == 1 or string.match(string.sub(line, from-1, from-1), "[%w_]") == nil) then
			return nil
		end

		-- has match instead of trigger (makes difference for regex)
		local cp = self:copy()
		self.trigger = trigger
		cp.captures = captures
		return cp
end

-- todo: impl exit_node
function Snippet:enter_node(node_id)
	if self.parent then
		self.parent:enter_node(self.indx)
	end

	local node = self.nodes[node_id]
	for _, other in ipairs(self.nodes) do
		if other.type ~= 0 then
			if util.mark_pos_equal(other.markers[2], node.markers[1]) then
				other:set_to_rgrav(false)
			else
				other:set_to_rgrav(true)
			end
		end
	end
	node:set_from_rgrav(false)
	node:set_to_rgrav(true)
	for i = node_id+1, #self.nodes, 1 do
		local other = self.nodes[i]
		if self.nodes[i].type ~= 0 then
			if util.mark_pos_equal(node.markers[2], other.markers[1]) then
				other:set_from_rgrav(true)
			else
				other:set_from_rgrav(false)
			end
			-- can be the case after expand; there all nodes without static text
			-- have left gravity on all marks.
			if util.mark_pos_equal(node.markers[2], other.markers[2]) then
				other:set_to_rgrav(true)
			end
		end
	end
end

-- https://gist.github.com/tylerneylon/81333721109155b2d244
local function copy3(obj, seen)
	-- Handle non-tables and previously-seen tables.
	if type(obj) ~= 'table' then return obj end
	if seen and seen[obj] then return seen[obj] end

	-- New table; mark it as seen an copy recursively.
	local s = seen or {}
	local res = {}
	s[obj] = res
	for k, v in next, obj do res[copy3(k, s)] = copy3(v, s) end
	return setmetatable(res, getmetatable(obj))
end

function Snippet:copy()
	return copy3(self)
end

function Snippet:set_text(node, text)
	local node_from = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[1], {})
	local node_to = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[2], {})

	self:enter_node(node.indx)
	if vim.o.expandtab then
	    local tab_string = string.rep(" ", vim.o.shiftwidth ~=0 and vim.o.shiftwidth or vim.o.tabstop)
        for i, str in ipairs(text) do
            text[i] = string.gsub(str, "\t", tab_string)
        end
    end
    vim.api.nvim_buf_set_text(0, node_from[1], node_from[2], node_to[1], node_to[2], text)
end

function Snippet:del_marks()
	for _, node in ipairs(self.nodes) do
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[1])
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[2])
	end
end

function Snippet:is_interactive()
	for _, node in ipairs(self.nodes) do
		-- return true if any node depends on another node or is an insertNode.
		if node.type == 1 or ((node.type == 2 or node.type == 5) and #node.args ~= 0) or node.type == 4 then
			return true
		-- node is snippet, recurse.
		elseif node.type == 3 then
			return node:is_interactive()
		end
	end
	return false
end

function Snippet:dump()
	for i, node in ipairs(self.nodes) do
		print(i)
		local c = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[1], {details = false})
		print(c[1], c[2])
		c = vim.api.nvim_buf_get_extmark_by_id(0, Luasnip_ns_id, node.markers[2], {details = false})
		print(c[1], c[2])
	end
end

function Snippet:put_initial()
	local cur = util.get_cursor_0ind()
	self.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = false})
	-- i needed for functions.
	for _, node in ipairs(self.nodes) do
		-- save cursor position for later.
		local cur1 = util.get_cursor_0ind()

		-- Gravities are set 'pointing inwards' for static text, any text inserted on the border to a insert belongs
		-- to the insert.

		-- leaves cursor behind last char of inserted text.
		node:put_initial()

		local cur2 = util.get_cursor_0ind()
		-- Will always have the same markers.
		if not (cur1[1] == cur2[1] and cur1[2] == cur2[2]) then
			-- place extmark directly on previously saved position (first char
			-- of inserted text) after putting text.
			node.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur1[1], cur1[2], {})
		-- zero-length; important that text put after doesn't move marker.
		else
			node.markers[1] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur1[1], cur1[2], {right_gravity = false})
		end

		-- place extmark directly behind last char of put text.
		node.markers[2] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur2[1], cur2[2], {right_gravity = false})
		node:set_old_text()
	end

	cur = util.get_cursor_0ind()
	self.markers[2] = vim.api.nvim_buf_set_extmark(0, Luasnip_ns_id, cur[1], cur[2], {right_gravity = true})
	self:set_old_text()

	for _, node in ipairs(self.nodes) do
		if node.type == 2 or node.type == 5 then
			if type(node.args[1]) ~= 'table' then
				-- append node to dependents-table of args.
				for i, arg in ipairs(node.args) do
					-- Function-Node contains refs. to arg-nodes.
					node.args[i] = self.insert_nodes[arg]
					self.insert_nodes[arg].dependents[#self.insert_nodes[arg].dependents+1] = node
				end
			end
		end
	end
end

function Snippet:update()
	for _, node in ipairs(self.nodes) do
		node:update()
	end
end

function Snippet:indent(line)
	local prefix = string.match(line, '^%s*')
	self.indentstr = prefix
	-- Check once here instead of inside loop.
	if vim.o.expandtab then
	    local tab_string = string.rep(" ", vim.o.shiftwidth ~=0 and vim.o.shiftwidth or vim.o.tabstop)
        for _, node in ipairs(self.nodes) do
            -- put prefix behind newlines.
            if node:has_static_text() then
                for i = 2, #node:get_static_text() do
                    -- Note: prefix is not changed but copied.
                    node:get_static_text()[i] = prefix .. string.gsub(node:get_static_text()[i], "\t", tab_string)
                end
            end
        end
    else
        for _, node in ipairs(self.nodes) do
            -- put prefix behind newlines.
            if node:has_static_text() then
                for i = 2, #node:get_static_text() do
                    node:get_static_text()[i] = prefix .. node:get_static_text()[i]
                end
            end
        end
    end
end

function Snippet:input_enter()
	self.active = true
end

function Snippet:input_leave()
	self:update_dependents()
	self.active = false
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
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[1])
		vim.api.nvim_buf_del_extmark(0, Luasnip_ns_id, node.markers[2])
	end
end

return {
	Snippet = Snippet,
	S = S,
	SN = SN
}
