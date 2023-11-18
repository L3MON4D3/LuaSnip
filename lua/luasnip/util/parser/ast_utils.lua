local Ast = require("luasnip.util.parser.neovim_ast")
local types = Ast.node_type
local util = require("luasnip.util.util")
local Str = require("luasnip.util.str")
local log = require("luasnip.util.log").new("parser")
local jsregexp_compile_safe = require("luasnip.util.jsregexp")

local directed_graph = require("luasnip.util.directed_graph")

local M = {}

---Walks ast pre-order, from left to right, applying predicate fn.
---The walk is aborted as soon as fn matches (eg. returns true).
---The walk does not recurse into Transform or choice, eg. it only covers nodes
---that can be jumped (in)to.
---@param ast table: the tree.
---@param fn function: the predicate.
---@return boolean: whether the predicate matched.
local function predicate_ltr_nodes(ast, fn)
	if fn(ast) then
		return true
	end
	for _, node in ipairs(ast.children or {}) do
		if predicate_ltr_nodes(node, fn) then
			return true
		end
	end

	return false
end

-- tested in vscode:
-- in "${1|b,c|} ${1:aa}" ${1:aa} is the copy,
-- in "${1:aa}, ${1|b,c|}" ${1|b,c} is the copy => with these two the position
-- determines which is the real tabstop => they have the same priority.
-- in "$1 ${1:aa}", $1 is the copy, so it has to have a lower priority.
local function type_real_tabstop_prio(node)
	local _type_real_tabstop_prio = {
		[types.TABSTOP] = 1,
		[types.PLACEHOLDER] = 2,
		[types.CHOICE] = 2,
	}
	if node.transform then
		return 0
	end
	return _type_real_tabstop_prio[node.type]
end

---The name of this function is horrible, but I can't come up with something
---more succinct.
---The idea here is to find which of two nodes is "smaller" in a
---"real-tabstop"-ordering relation on all the nodes of a snippet.
---REQUIREMENT!!! The nodes have to be passed in the order they appear in in
---the snippet, eg. prev_node has to appear earlier in the text (or be a parent
---of) current_node.
---@param prev_node table: the ast node earlier in the text.
---@param current_node table: the other ast node.
---@return boolean: true if prev_node is less than (according to the
---"real-tabstop"-ordering described above and in the docstring of
---`add_dependents`), false otherwise.
local function real_tabstop_order_less(prev_node, current_node)
	local prio_prev = type_real_tabstop_prio(prev_node)
	local prio_current = type_real_tabstop_prio(current_node)
	-- if type-prio is the same, the one that appeared earlier is the real tabstop.
	return prio_prev == prio_current and false or prio_prev < prio_current
end

---Find the real (eg. the one that is not a copy) $0.
---@param ast table: ast
---@return number, number, boolean: first, the type of the node with position 0, then
--- the child of `ast` containing it and last whether the real $0 is copied.
local function real_zero_node(ast)
	local real_zero = nil
	local real_zero_indx = nil
	local is_copied = false

	local _search_zero
	_search_zero = function(node)
		local had_zero = false
		-- find placeholder/tabstop/choice with position 0
		if node.tabstop == 0 then
			if not real_zero then
				real_zero = node
				had_zero = true
			else
				if real_tabstop_order_less(real_zero, node) then
					-- node has a higher prio than the current real_zero.
					real_zero = node
					had_zero = true
				end
				-- we already encountered a zero-node, since i(0) cannot be
				-- copied this has to be reported to the caller.
				is_copied = true
			end
		end
		for indx, child in ipairs(node.children or {}) do
			local zn, _ = _search_zero(child)
			-- due to recursion, this will be called last in the loop of the
			-- outermost snippet.
			-- real_zero_indx will be the position of the child of snippet, in
			-- which the real $0 is located.
			if zn then
				real_zero_indx = indx
				had_zero = true
			end
		end

		return had_zero
	end
	_search_zero(ast)

	return real_zero, real_zero_indx, is_copied
end

local function count_tabstop(ast, tabstop_indx)
	local count = 0

	predicate_ltr_nodes(ast, function(node)
		if node.tabstop == tabstop_indx then
			count = count + 1
		end
		-- only stop once all nodes were looked at.
		return false
	end)

	return count
end

local function text_only_placeholder(placeholder)
	local only_text = true

	predicate_ltr_nodes(placeholder, function(node)
		if node == placeholder then
			-- ignore placeholder.
			return false
		end
		if node.type ~= types.TEXT then
			only_text = false
			-- we found non-text, no need to search more.
			return true
		end
	end)

	return only_text
end

local function max_position(ast)
	local max = 0
	predicate_ltr_nodes(ast, function(node)
		local new_max = node.tabstop or 0
		if new_max > max then
			max = new_max
		end
		-- don't stop early.
		return false
	end)

	return max
end

local function replace_position(ast, p1, p2)
	predicate_ltr_nodes(ast, function(node)
		if node.tabstop == p1 then
			node.tabstop = p2
		end
		-- look at all nodes.
		return false
	end)
end

function M.fix_zero(ast)
	local zn, ast_child_with_0_indx, is_copied = real_zero_node(ast)
	-- if zn exists, is a tabstop, an immediate child of `ast`, and does not
	-- have to be copied, the snippet can be accurately represented by luasnip.
	-- (also if zn just does not exist, ofc).
	--
	-- If the snippet can't be represented as-is, the ast needs to be modified
	-- as described below.
	if
		not zn
		or (
			zn
			and not is_copied
			and (zn.type == types.TABSTOP or (zn.type == types.PLACEHOLDER and text_only_placeholder(
				zn
			)))
			and ast.children[ast_child_with_0_indx] == zn
		)
	then
		return
	end

	-- bad, a choice or placeholder is at position 0.
	-- replace all ${0:...} with ${n+1:...} (n highest position)
	-- max_position is at least 0, all's good.
	local max_pos = max_position(ast)
	replace_position(ast, 0, max_pos + 1)

	-- insert $0 as a direct child to snippet, just behind the original $0/the
	-- node containing it.
	table.insert(ast.children, ast_child_with_0_indx + 1, Ast.tabstop(0))
end

---This function identifies which tabstops/placeholder/choices are copies, and
---which are "real tabstops"(/choices/placeholders). The real tabstops are
---extended with a list of their dependents (tabstop.dependents), the copies
---with their real tabstop (copy.copies)
---
---Rules for which node of any two nodes with the same tabstop-index is the
---real tabstop:
--- - if one is a tabstop and the other a placeholder/choice, the
---   placeholder/choice is the real tabstop.
--- - if they are both tabstop or both placeholder/choice, the one which
---   appears earlier in the snippet is the real tabstop.
---   (in "${1: ${1:lel}}" the outer ${1:...} appears earlier).
---
---@param ast table: the AST.
function M.add_dependents(ast)
	-- all nodes that have a tabstop.
	-- map tabstop-index (number) -> node.
	local tabstops = {}

	-- nodes which copy some tabstop.
	-- map tabstop-index (number) -> node[] (since there could be multiple copies of that one snippet).
	local copies = {}

	predicate_ltr_nodes(ast, function(node)
		if not node.tabstop then
			-- not a tabstop-node -> continue.
			return false
		end

		if not tabstops[node.tabstop] then
			tabstops[node.tabstop] = node
			-- continue, we want to find all dependencies.
			return false
		end
		if not copies[node.tabstop] then
			copies[node.tabstop] = {}
		end
		if real_tabstop_order_less(tabstops[node.tabstop], node) then
			table.insert(copies[node.tabstop], tabstops[node.tabstop])
			tabstops[node.tabstop] = node
		else
			table.insert(copies[node.tabstop], node)
		end
		-- continue.
		return false
	end)

	-- associate real tabstop with its copies (by storing the copies in the real tabstop).
	for i, real_tabstop in pairs(tabstops) do
		real_tabstop.dependents = {}
		for _, copy in ipairs(copies[i] or {}) do
			table.insert(real_tabstop.dependents, copy)
			copy.copies = real_tabstop
		end
	end
end

local function apply_modifier(text, modifier)
	local mod_fn = Str.vscode_string_modifiers[modifier]
	if mod_fn then
		return mod_fn(text)
	else
		-- this can't really be reached, since only correct and available
		-- modifiers are parsed successfully
		-- (https://github.com/L3MON4D3/LuaSnip/blob/5fbebf6409f86bc4b7b699c2c80745e1ed190c16/lua/luasnip/util/parser/neovim_parser.lua#L239-L245).
		log.warn(
			"Tried to apply unknown modifier `%s` while parsing snippet, recovering by applying identity instead.",
			modifier
		)
		return text
	end
end

local function apply_transform_format(nodes, captures)
	local transformed = ""
	for _, node in ipairs(nodes) do
		if node.type == types.TEXT then
			transformed = transformed .. node.esc
		else
			local capture = captures[node.capture_index]
			-- capture exists if it ..exists.. and is nonempty.
			if capture and #capture > 0 then
				if node.if_text then
					transformed = transformed .. node.if_text
				elseif node.modifier then
					transformed = transformed
						.. apply_modifier(capture, node.modifier)
				else
					transformed = transformed .. capture
				end
			else
				if node.else_text then
					transformed = transformed .. node.else_text
				end
			end
		end
	end

	return transformed
end

function M.apply_transform(transform)
	if jsregexp_compile_safe then
		local reg_compiled, err =
			jsregexp_compile_safe(transform.pattern, transform.option)

		if reg_compiled then
			-- can be passed to functionNode!
			return function(lines)
				-- luasnip expects+passes lines as list, but regex needs one string.
				lines = table.concat(lines, "\n")
				local matches = reg_compiled(lines)

				local transformed = ""
				-- index one past the end of previous match.
				-- This is used to append unmatched characters to `transformed`, so
				-- it's initialized such that the first append is from 1.
				local prev_match_end = 0
				for _, match in ipairs(matches) do
					-- begin_ind and end_ind are inclusive.
					transformed = transformed
						.. lines:sub(prev_match_end + 1, match.begin_ind - 1)
						.. apply_transform_format(
							transform.format,
							match.groups
						)

					-- end-inclusive
					prev_match_end = match.end_ind
				end
				transformed = transformed
					.. lines:sub(prev_match_end + 1, #lines)

				return vim.split(transformed, "\n")
			end
		else
			log.error(
				"Failed parsing regex `%s` with options `%s`: %s",
				transform.pattern,
				transform.option,
				err
			)
			-- fall through to returning identity.
		end
	end

	-- without jsregexp, or without a valid regex, we cannot properly transform
	-- whatever is supposed to be transformed here.
	-- Just return a function that returns the to-be-transformed string
	-- unmodified.
	return util.id
end

---Variables need the text which is in front of them to determine whether they
---have to be indented ("asdf\n\t$TM_SELECTED_TEXT": vscode indents all lines
---of TM_SELECTED_TEXT).
---
---The text is accessible as ast_node.previous_text, a string[].
---@param ast table: the AST.
function M.give_vars_previous_text(ast)
	local last_text = { "" }
	-- important: predicate_ltr_nodes visits the node in the order they appear,
	-- textually, in the snippet.
	-- This is necessary to actually ensure the variables actually get the text just in front of them.
	predicate_ltr_nodes(ast, function(node)
		if node.children then
			-- continue if this node is not a leaf.
			-- Since predicate_ltr_nodes runs fn first for the placeholder, and
			-- then for its' children, `last_text` would be reset wrongfully
			-- (example: "asdf\n\t${1:$TM_SELECTED_TEXT}". Here the placeholder
			-- is encountered before the variable -> no indentation).
			--
			-- ignoring non-leaf-nodes makes it so that only the nodes which
			-- actually contribute text (placeholders are "invisible" in that
			-- they don't add text themselves, they do it through their
			-- children) are considered.
			return false
		end
		if node.type == types.TEXT then
			last_text = vim.split(node.esc, "\n")
		elseif node.type == types.VARIABLE then
			node.previous_text = last_text
		else
			-- reset last_text when a different node is encountered.
			last_text = { "" }
		end
		-- continue..
		return false
	end)
end

---Variables are turned into placeholders if the Variable is undefined or not set.
---Since in luasnip, variables can be added at runtime, the decision whether a
---variable is just some text, inserts its default, or its variable-name has to
---be deferred to runtime.
---So, each variable is a dynamicNode, and needs a tabstop.
---In vscode the variables are visited
--- 1) after all other tabstops/placeholders/choices and
--- 2) in the order they appear in the snippet-body.
---We mimic this behaviour.
---@param ast table: The AST.
function M.give_vars_potential_tabstop(ast)
	local last_tabstop = max_position(ast)

	predicate_ltr_nodes(ast, function(node)
		if node.type == types.VARIABLE then
			last_tabstop = last_tabstop + 1
			node.potential_tabstop = last_tabstop
		end
	end)
end

function M.parse_order(ast)
	M.add_dependents(ast)
	-- build Directed Graph from ast-nodes.
	-- vertices are ast-nodes, edges define has-to-be-parsed-before-relations
	-- (a child of some placeholder would have an edge to it, real tabstops
	-- have edges to their copies).
	local g = directed_graph.new()
	-- map node -> vertex.
	local to_vert = {}

	-- add one vertex for each node + create map node->vert.
	predicate_ltr_nodes(ast, function(node)
		to_vert[node] = g:add_vertex()
	end)

	predicate_ltr_nodes(ast, function(node)
		if node.dependents then
			-- if the node has dependents, it has to be parsed before they are.
			for _, dep in ipairs(node.dependents) do
				g:set_edge(to_vert[node], to_vert[dep])
			end
		end
		if node.children then
			-- if the node has children, they have to be parsed before it can
			-- be parsed.
			for _, child in ipairs(node.children) do
				g:set_edge(to_vert[child], to_vert[node])
			end
		end
	end)

	local topsort = g:topological_sort()
	if not topsort then
		-- ast (with additional dependencies) contains circle.
		return nil
	end

	local to_node = util.reverse_lookup(to_vert)
	return vim.tbl_map(function(vertex)
		return to_node[vertex]
	end, topsort)
end

M.types = types

return M
