local types = require("luasnip.util.parser.neovim_ast").node_type
local Node_mt = getmetatable(
	require("luasnip.util.parser.neovim_parser").parse("$0")
)
local util = require("luasnip.util.util")
local jsregexp_ok, jsregexp = pcall(require, "jsregexp")

local M = {}

--- Find type of 0-placeholder/choice/tabstop, if it exists.
--- Ignores transformations.
---@param ast table: ast
---@return number, number: first, the type of the node with position 0, then
--- the child of `ast` containing it.
local function zero_node(ast)
	-- find placeholder/tabstop/choice with position 0, but ignore those that
	-- just apply transformations, this should return the node where the cursor
	-- ends up on exit.
	-- (this node should also exist in this snippet, as long as it was formatted
	-- correctly).
	if ast.tabstop == 0 and not ast.transform then
		return ast
	end
	for indx, child in ipairs(ast.children or {}) do
		local zn, _ = zero_node(child)
		if zn then
			return zn, indx
		end
	end

	-- no 0-node in this ast.
	return nil, nil
end

local function max_position(ast)
	local max = ast.tabstop or -1

	for _, child in ipairs(ast.children or {}) do
		local mp = max_position(child)
		if mp > max then
			max = mp
		end
	end

	return max
end

local function replace_position(ast, p1, p2)
	if ast.tabstop == p1 then
		ast.tabstop = p2
	end
	for _, child in ipairs(ast.children or {}) do
		replace_position(child, p1, p2)
	end
end

function M.fix_zero(ast)
	local zn, ast_child_with_0_indx = zero_node(ast)
	-- if zn exists, is a tabstop and an immediate child of `ast`, the snippet can
	-- be accurately represented by luasnip (also if zn does not exist, ofc).
	-- Otherwise the ast needs to be modified as described below.
	if
		not zn
		or (
			zn
			and zn.type == types.TABSTOP
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

	-- insert $0 as a direct child to snippet.
	table.insert(
		ast.children,
		ast_child_with_0_indx + 1,
		setmetatable({
			type = types.TABSTOP,
			tabstop = 0,
		}, Node_mt)
	)
end

local modifiers = setmetatable({
	upcase = string.upper,
	downcase = string.lower,
	capitalize = function(string)
		-- uppercase first character only.
		return string:sub(1, 1):upper() .. string:sub(2, -1)
	end,
}, {
	__index = function()
		-- return string unmodified.
		-- TODO: log an error/warning here.
		return util.id
	end,
})
local function apply_modifier(text, modifier)
	Insp(modifier)
	return modifiers[modifier](text)
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
	if jsregexp_ok then
		local reg_compiled = jsregexp.compile(
			transform.pattern,
			transform.option
		)
		-- can be passed to functionNode!
		return function(lines)
			-- luasnip expects+passes lines as list, but regex needs one string.
			lines = table.concat(lines, "\\n")
			local matches = reg_compiled(lines)

			local transformed = ""
			-- index one past the end of previous match.
			-- This is used to append unmatched characters to `transformed`, so
			-- it's initialized with 1.
			local prev_match_end = 1
			for _, match in ipairs(matches) do
				-- -1: begin_ind is inclusive.
				transformed = transformed
					.. lines:sub(prev_match_end, match.begin_ind - 1)
					.. apply_transform_format(transform.format, match.groups)

				-- end-exclusive
				prev_match_end = match.end_ind
			end
			transformed = transformed .. lines:sub(prev_match_end, #lines)

			return vim.split(transformed, "\n")
		end
	else
		-- without jsregexp, we cannot properly transform whatever is supposed to
		-- be transformed here.
		-- Just return a function that returns the to-be-transformed string
		-- unmodified.
		return util.id
	end
end

M.types = types
M.Node_mt = Node_mt
return M
