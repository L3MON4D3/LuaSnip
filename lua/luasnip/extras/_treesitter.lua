local util = require("luasnip.util.util")
local tbl = require("luasnip.util.table")

local function get_lang(bufnr)
	local ft = vim.api.nvim_buf_get_option(bufnr, "ft")
	local lang = vim.treesitter.language.get_lang(ft) or ft
	return lang
end

-- Inspect node
---@param node TSNode?
---@return string
local function inspect_node(node)
	if node == nil then
		return "nil"
	end

	local start_row, start_col, end_row, end_col =
		vim.treesitter.get_node_range(node)

	return ("%s [%d, %d] [%d, %d]"):format(
		node:type(),
		start_row,
		start_col,
		end_row,
		end_col
	)
end

---@param bufnr number
---@param region LuaSnip.MatchRegion
---@return LanguageTree, string
local function reparse_buffer_after_removing_match(bufnr, region)
	local lang = get_lang(bufnr)

	-- have to get entire buffer, a pattern-match may include lines behind the trigger.
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	-- region is 0-indexed, lines and strings 1-indexed.
	local region_line = lines[region.row + 1]
	-- sub includes end, want to exclude it.
	local left_part = region_line:sub(1, region.col_range[1] + 1 - 1)
	local right_part = region_line:sub(region.col_range[2] + 1)

	lines[region.row + 1] = left_part .. right_part

	local source = table.concat(lines, "\n")

	---@type LanguageTree
	local parser = vim.treesitter.get_string_parser(source, lang, nil)
	parser:parse()
	return parser, source
end

---@class LuaSnip.extra.FixBufferContext
---@field ori_bufnr number
---@field ori_text string
---@field region LuaSnip.MatchRegion
local FixBufferContext = {}

---@param ori_bufnr number
---@param region LuaSnip.MatchRegion
---@return LuaSnip.extra.FixBufferContext
function FixBufferContext.new(ori_bufnr, region, region_content)
	local o = {
		ori_bufnr = ori_bufnr,
		ori_text = region_content,
		region = region,
	}
	setmetatable(o, {
		__index = FixBufferContext,
	})

	return o
end

function FixBufferContext:enter()
	vim.api.nvim_buf_set_text(
		self.ori_bufnr,
		self.region.row,
		self.region.col_range[1],
		self.region.row,
		self.region.col_range[2],
		{ "" }
	)

	local parser, source =
		vim.treesitter.get_parser(self.ori_bufnr), self.ori_bufnr
	parser:parse()

	return parser, source
end

function FixBufferContext:leave()
	vim.api.nvim_buf_set_text(
		self.ori_bufnr,
		self.region.row,
		self.region.col_range[1],
		self.region.row,
		self.region.col_range[1],
		{ self.ori_text }
	)

	-- The cursor does not necessarily move with the insertion, and has to be
	-- restored manually.
	-- when making this work for expansion away from cursor, store cursor-pos
	-- in self.
	vim.api.nvim_win_set_cursor(
		0,
		{ self.region.row + 1, self.region.col_range[2] }
	)

	local parser, source =
		vim.treesitter.get_parser(self.ori_bufnr), self.ori_bufnr
	parser:parse()
	return parser, source
end

-- iterate over all
local function captures_iter(captures)
	-- turn string/string[] into map: string -> bool, for querying whether some
	-- string is present in captures.
	local capture_map = tbl.list_to_set(captures)

	-- receives the query and the iterator over all its matches.
	return function(query, match_iter)
		local current_match
		local current_capture_id
		local iter

		iter = function()
			-- if there is no current match to continue,
			if not current_match then
				_, current_match, _ = match_iter()

				-- occurs once there are no more matches.
				if not current_match then
					return nil
				end
			end
			while true do
				local node
				current_capture_id, node =
					next(current_match, current_capture_id)
				if not current_capture_id then
					break
				end

				local capture_name = query.captures[current_capture_id]

				if capture_map[capture_name] then
					return current_match, node
				end
			end

			-- iterated over all captures of the current match, reset it to
			-- retrieve the next match in the recursion.
			current_match = nil

			-- tail-call-optimization! :fingers_crossed:
			return iter()
		end

		return iter
	end
end

local builtin_tsnode_selectors = {
	any = function()
		local best_node
		local best_node_match
		return {
			record = function(match, node)
				best_node = node
				best_node_match = match
				-- abort immediately, we just want any match.
				return true
			end,
			retrieve = function()
				return best_node_match, best_node
			end,
		}
	end,
	shortest = function()
		local best_node
		local best_node_match

		-- end is already equal, only have to compare start.
		local best_node_start
		return {
			record = function(match, node)
				local start_row, start_col, _, _ =
					vim.treesitter.get_node_range(node)
				if
					(best_node == nil)
					or (start_row > best_node_start[1])
					or (
						start_row == best_node_start[1]
						and start_col > best_node_start[2]
					)
				then
					best_node = node
					best_node_match = match
					best_node_start = { start_row, start_col }
				end
				-- don't abort, have to see all potential nodes to find shortest match.
				return false
			end,
			retrieve = function()
				return best_node_match, best_node
			end,
		}
	end,
	longest = function()
		local best_node
		local best_node_match

		-- end is already equal, only have to compare start.
		local best_node_start
		return {
			record = function(match, node)
				local start_row, start_col, _, _ =
					vim.treesitter.get_node_range(node)
				if
					(best_node == nil)
					or (start_row < best_node_start[1])
					or (
						start_row == best_node_start[1]
						and start_col < best_node_start[2]
					)
				then
					best_node = node
					best_node_match = match
					best_node_start = { start_row, start_col }
				end
				-- don't abort, have to see all potential nodes to find longest match.
				return false
			end,
			retrieve = function()
				return best_node_match, best_node
			end,
		}
	end,
}

---@class LuaSnip.extra.TSParser
---@field parser LanguageTree
---@field source string|number
local TSParser = {}

---@param bufnr number?
---@param parser LanguageTree
---@param source string|number
---@return LuaSnip.extra.TSParser?
function TSParser.new(bufnr, parser, source)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local o = {
		parser = parser,
		source = source,
	}

	setmetatable(o, {
		__index = TSParser,
		---@param self LuaSnip.extra.TSParser
		---@return string
		__tostring = function(self)
			return ("trees: %d, source: %s"):format(
				#self.parser:trees(),
				type(self.source) == "number" and tostring(self.source)
					or "[COPIED]"
			)
		end,
	})
	return o
end

---@param pos { [1]: number, [2]: number }?
---@return TSNode?
function TSParser:get_node_at_pos(pos)
	pos = vim.F.if_nil(pos, util.get_cursor_0ind())
	local row, col = pos[1], pos[2]
	assert(
		row >= 0 and col >= 0,
		"Invalid position: row and col must be non-negative"
	)
	local range = { row, col, row, col }
	return self.parser:named_node_for_range(
		range,
		{ ignore_injections = false }
	)
end

---Get the root for the smallest tree containing `pos`.
---@param pos { [1]: number, [2]: number }
---@return TSNode?
function TSParser:root_at(pos)
	local tree = self.parser:tree_for_range(
		{ pos[1], pos[2], pos[1], pos[2] },
		{ ignore_injections = false }
	)
	if not tree then
		return nil
	end

	return tree:root()
end

---@param match_opts LuaSnip.extra.EffectiveMatchTSNodeOpts
---@param pos { [1]: number, [2]: number }
---@return LuaSnip.extra.NamedTSMatch?, TSNode?
function TSParser:match_at(match_opts, pos)
	-- Since we want to find a match to the left of pos, and if we accept there
	-- has to be at least one character (I assume), we should probably not look
	-- for the tree containing `pos`, since that might be the wrong one (if
	-- injected languages are in play).
	local root = self:root_at({ pos[1], pos[2] - 1 })
	if root == nil then
		return nil, nil
	end
	local root_from_line, _, root_to_line, _ = root:range()

	local query = match_opts.query
	local selector = match_opts.selector()
	local next_ts_match =
		-- end-line is excluded by iter_matches, if the column of root_to
		-- greater than 0, we would erroneously ignore a line that could
		-- contain our match.
		query:iter_matches(root, self.source, root_from_line, root_to_line + 1)

	for match, node in match_opts.generator(query, next_ts_match) do
		-- false: don't include bytes.
		local _, _, end_row, end_col = node:range(false)
		if end_row == pos[1] and end_col == pos[2] then
			if selector.record(match, node) then
				-- should abort iteration
				break
			end
		end
	end

	local best_match, node = selector.retrieve()
	if not best_match then
		return nil, nil
	end

	-- map captures via capture-name, not id.
	local named_captures_match = {}
	for id, capture_node in pairs(best_match) do
		named_captures_match[query.captures[id]] = capture_node
	end
	return named_captures_match, node
end

---@param node TSNode
---@return string
function TSParser:get_node_text(node)
	-- not sure what happens if this is multiline.
	return vim.treesitter.get_node_text(node, self.source)
end

---@param root TSNode
---@param n number
---@param matcher fun(node:TSNode):boolean|nil
---@return TSNode?
local function find_nth_parent(root, n, matcher)
	local parent = root
	matcher = matcher or function()
		return true
	end
	local i = 0
	while i < n do
		if not parent or not matcher(parent) then
			return nil
		end
		parent = parent:parent()
		i = i + 1
	end
	if not parent or not matcher(parent) then
		return nil
	end
	return parent
end

---@param root TSNode
---@param matcher fun(node:TSNode):boolean|nil
local function find_topmost_parent(root, matcher)
	---@param node TSNode?
	---@return TSNode?
	local function _impl(node)
		if node == nil then
			return nil
		end
		local current = nil
		if matcher == nil or matcher(node) then
			current = node
		end
		return vim.F.if_nil(_impl(node:parent()), current)
	end

	return _impl(root)
end

---@param root TSNode
---@param matcher fun(node:TSNode):boolean|nil
local function find_first_parent(root, matcher)
	---@param node TSNode?
	---@return TSNode?
	local function _impl(node)
		if node == nil then
			return nil
		end
		if matcher == nil or matcher(node) then
			return node
		end
		return _impl(node:parent())
	end

	return _impl(root)
end

return {
	get_lang = get_lang,
	reparse_buffer_after_removing_match = reparse_buffer_after_removing_match,
	TSParser = TSParser,
	FixBufferContext = FixBufferContext,
	find_topmost_parent = find_topmost_parent,
	find_first_parent = find_first_parent,
	find_nth_parent = find_nth_parent,
	inspect_node = inspect_node,
	captures_iter = captures_iter,
	builtin_tsnode_selectors = builtin_tsnode_selectors,
}
