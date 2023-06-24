local session = require("luasnip.session")

-- jsregexp: first try loading the version installed by luasnip, then global ones.
local jsregexp_ok, jsregexp = pcall(require, "luasnip-jsregexp")
if not jsregexp_ok then
	jsregexp_ok, jsregexp = pcall(require, "jsregexp")
end

local function get_cursor_0ind()
	local c = vim.api.nvim_win_get_cursor(0)
	c[1] = c[1] - 1
	return c
end

-- don't use utf-indexed column, win_set_cursor ignores these.
local function set_cursor_0ind(c)
	c[1] = c[1] + 1
	vim.api.nvim_win_set_cursor(0, c)
end

-- pos: (0,0)-indexed.
local function line_chars_before(pos)
	-- cur-rows are 1-indexed, api-rows 0.
	local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)
	return string.sub(line[1], 1, pos[2])
end

-- returns current line with text up-to and excluding the cursor.
local function get_current_line_to_cursor()
	return line_chars_before(get_cursor_0ind())
end

-- delete n chars before cursor, MOVES CURSOR
local function remove_n_before_cur(n)
	local cur = get_cursor_0ind()
	vim.api.nvim_buf_set_text(0, cur[1], cur[2] - n, cur[1], cur[2], { "" })
	cur[2] = cur[2] - n
	set_cursor_0ind(cur)
end

-- in-place modifies the table.
local function dedent(text, indentstring)
	-- 2 because 1 shouldn't contain indent.
	for i = 2, #text do
		text[i] = text[i]:gsub("^" .. indentstring, "")
	end
	return text
end

-- in-place insert indenstrig before each line.
local function indent(text, indentstring)
	for i = 2, #text - 1, 1 do
		-- only indent if there is actually text.
		if #text[i] > 0 then
			text[i] = indentstring .. text[i]
		end
	end
	-- assuming that the last line should be indented as it is probably
	-- followed by some other node, therefore isn't an empty line.
	if #text > 1 then
		text[#text] = indentstring .. text[#text]
	end
	return text
end

--- In-place expands tabs in `text`.
--- Difficulties:
--- we cannot simply replace tabs with a given number of spaces, the tabs align
--- text at multiples of `tabwidth`. This is also the reason we need the number
--- of columns the text is already indented by (otherwise we can only start a 0).
---@param text string[], multiline string.
---@param tabwidth number, displaycolumns one tab should shift following text
--- by.
---@param parent_indent_displaycolumns number, displaycolumn this text is
--- already at.
---@return string[], `text` (only for simple nesting).
local function expand_tabs(text, tabwidth, parent_indent_displaycolumns)
	for i, line in ipairs(text) do
		local new_line = ""
		local start_indx = 1
		while true do
			local tab_indx = line:find("\t", start_indx, true)
			-- if no tab found, sub till end (ie. -1).
			new_line = new_line .. line:sub(start_indx, (tab_indx or 0) - 1)
			if tab_indx then
				-- #new_line is index of this tab in new_line.
				new_line = new_line
					.. string.rep(
						" ",
						tabwidth
							- (
								(parent_indent_displaycolumns + #new_line)
								% tabwidth
							)
					)
			else
				-- reached end of string.
				break
			end
			start_indx = tab_indx + 1
		end
		text[i] = new_line
	end
	return text
end

local function tab_width()
	return vim.bo.shiftwidth ~= 0 and vim.bo.shiftwidth or vim.bo.tabstop
end

local function mark_pos_equal(m1, m2)
	local p1 = vim.api.nvim_buf_get_extmark_by_id(0, session.ns_id, m1, {})
	local p2 = vim.api.nvim_buf_get_extmark_by_id(0, session.ns_id, m2, {})
	return p1[1] == p2[1] and p1[2] == p2[2]
end

local function move_to_mark(id)
	local new_cur_pos
	new_cur_pos = vim.api.nvim_buf_get_extmark_by_id(
		0,
		session.ns_id,
		id,
		{ details = false }
	)
	set_cursor_0ind(new_cur_pos)
end

local function bytecol_to_utfcol(pos)
	local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)
	-- line[1]: get_lines returns table.
	return { pos[1], vim.str_utfindex(line[1] or "", pos[2]) }
end

local function replace_feedkeys(keys, opts)
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes(keys, true, false, true),
		-- folds are opened manually now, no need to pass t.
		-- n prevents langmap from interfering.
		opts or "n",
		true
	)
end

-- pos: (0,0)-indexed.
local function cursor_set_keys(pos, before)
	if before then
		if pos[2] == 0 then
			pos[1] = pos[1] - 1
			-- pos2 is set to last columnt of previous line.
			-- # counts bytes, but win_set_cursor expects bytes, so all's good.
			pos[2] =
				#vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)[1]
		else
			pos[2] = pos[2] - 1
		end
	end

	return "<cmd>lua vim.api.nvim_win_set_cursor(0,{"
		-- +1, win_set_cursor starts at 1.
		.. pos[1] + 1
		.. ","
		-- -1 works for multibyte because of rounding, apparently.
		.. pos[2]
		.. "})"
		.. "<cr><cmd>:silent! foldopen!<cr>"
end

-- any for any mode.
-- other functions prefixed with eg. normal have to be in that mode, the
-- initial esc removes that need.
local function any_select(b, e)
	-- stylua: ignore
	replace_feedkeys(
		-- this esc -> movement sometimes leads to a slight flicker
		-- TODO: look into preventing that reliably.
		-- simple move -> <esc>v isn't possible, leaving insert moves the
		-- cursor, maybe do check for mode beforehand.
		"<esc>"
		.. cursor_set_keys(b)
		.. "v"
		.. (vim.o.selection == "exclusive" and
			cursor_set_keys(e) or
			-- set before
			cursor_set_keys(e, true))
		.. "o<C-G><C-r>_" )
end

local function normal_move_on_insert(new_cur_pos)
	-- moving in normal and going into insert is kind of annoying, eg. when the
	-- cursor is, in normal, on a tab, i will set it on the beginning of the
	-- tab. There's more problems, but this is very safe.
	replace_feedkeys("i" .. cursor_set_keys(new_cur_pos))
end

local function insert_move_on(new_cur_pos)
	-- maybe feedkeys this too.
	set_cursor_0ind(new_cur_pos)
	vim.api.nvim_command("redraw!")
end

local function multiline_equal(t1, t2)
	for i, line in ipairs(t1) do
		if line ~= t2[i] then
			return false
		end
	end

	return #t1 == #t2
end

local function word_under_cursor(cur, line)
	local ind_start = 1
	local ind_end = #line

	while true do
		local tmp = string.find(line, "%W%w", ind_start)
		if not tmp then
			break
		end
		if tmp > cur[2] + 1 then
			break
		end
		ind_start = tmp + 1
	end

	local tmp = string.find(line, "%w%W", cur[2] + 1)
	if tmp then
		ind_end = tmp
	end

	return string.sub(line, ind_start, ind_end)
end

-- Put text and update cursor(pos) where cursor is byte-indexed.
local function put(text, pos)
	vim.api.nvim_buf_set_text(0, pos[1], pos[2], pos[1], pos[2], text)
	-- add rows
	pos[1] = pos[1] + #text - 1
	-- add columns, start at 0 if no rows were added, else at old col-value.
	pos[2] = (#text > 1 and 0 or pos[2]) + #text[#text]
end

--[[ Wraps the value in a table if it's not one, makes
  the first element an empty str if the table is empty]]
local function to_string_table(value)
	if not value then
		return { "" }
	end
	if type(value) == "string" then
		return { value }
	end
	-- at this point it's a table
	if #value == 0 then
		return { "" }
	end
	-- non empty table
	return value
end

-- Wrap node in a table if it is not one
local function wrap_nodes(nodes)
	-- safe to assume, if nodes has a metatable, it is a single node, not a
	-- table.
	if getmetatable(nodes) and nodes.type then
		return { nodes }
	else
		return nodes
	end
end

local SELECT_RAW = "LUASNIP_SELECT_RAW"
local SELECT_DEDENT = "LUASNIP_SELECT_DEDENT"
local TM_SELECT = "LUASNIP_TM_SELECT"

local function get_selection()
	local ok, val = pcall(vim.api.nvim_buf_get_var, 0, SELECT_RAW)
	if ok then
		local result = {
			val,
			vim.api.nvim_buf_get_var(0, SELECT_DEDENT),
			vim.api.nvim_buf_get_var(0, TM_SELECT),
		}

		vim.api.nvim_buf_del_var(0, SELECT_RAW)
		vim.api.nvim_buf_del_var(0, SELECT_DEDENT)
		vim.api.nvim_buf_del_var(0, TM_SELECT)

		return unpack(result)
	end
	return {}, {}, {}
end

local function get_min_indent(lines)
	-- "^(%s*)%S": match only lines that actually contain text.
	local min_indent = lines[1]:match("^(%s*)%S")
	for i = 2, #lines do
		-- %s* -> at least matches
		local line_indent = lines[i]:match("^(%s*)%S")
		-- ignore if not matched.
		if line_indent then
			-- if no line until now matched, use line_indent.
			if not min_indent or #line_indent < #min_indent then
				min_indent = line_indent
			end
		end
	end
	return min_indent
end

-- there's probably a better way to do this.
local function byte_start_to_byte_end(pos)
	local line = vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)
	-- line[1]: get_lines returns table.
	-- col may be one past the end (for linebreak)
	-- byteindex rounds toward end of the multibyte-character.
	return vim.str_byteindex(
		line[1] .. " " or "",
		vim.str_utfindex(line[1] .. " " or "", pos[2])
	)
end

local function store_selection()
	local start_line, start_col = vim.fn.line("'<"), vim.fn.col("'<")

	local end_line = vim.fn.line("'>")
	-- col of '>/'< is the first byte, in case of multibyte. As the entire
	-- multibyte-string has to be in the selection, this needs to be converted.
	local end_col = byte_start_to_byte_end({ end_line - 1, vim.fn.col("'>") })

	local mode = vim.fn.visualmode()
	if
		not vim.o.selection == "exclusive"
		and not (start_line == end_line and start_col == end_col)
	then
		end_col = end_col - 1
	end

	local chunks = {}
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, true)
	if start_line == end_line then
		chunks = { lines[1]:sub(start_col, end_col) }
	else
		local first_col = 0
		local last_col = nil
		if mode:lower() ~= "v" then -- mode is block
			first_col = start_col
			last_col = end_col
		end
		chunks = { lines[1]:sub(start_col, last_col) }

		-- potentially trim lines (Block).
		for cl = 2, #lines - 1 do
			table.insert(chunks, lines[cl]:sub(first_col, last_col))
		end
		table.insert(chunks, lines[#lines]:sub(first_col, end_col))
	end

	-- init with raw selection.
	local tm_select, select_dedent = vim.deepcopy(chunks), vim.deepcopy(chunks)
	-- may be nil if no indent.
	local min_indent = get_min_indent(lines) or ""
	-- TM_SELECTED_TEXT contains text from new cursor position(for V the first
	-- non-whitespace of first line, v and c-v raw) to end of selection.
	if mode == "V" then
		tm_select[1] = tm_select[1]:gsub("^%s+", "")
		-- remove indent from all lines:
		for i = 1, #select_dedent do
			select_dedent[i] = select_dedent[i]:gsub("^" .. min_indent, "")
		end
	elseif mode == "v" then
		-- if selection starts inside indent, remove indent.
		if #min_indent > start_col then
			select_dedent[1] = lines[1]:gsub(min_indent, "")
		end
		for i = 2, #select_dedent - 1 do
			select_dedent[i] = select_dedent[i]:gsub(min_indent, "")
		end

		-- remove as much indent from the last line as possible.
		if #min_indent > end_col then
			select_dedent[#select_dedent] = ""
		else
			select_dedent[#select_dedent] =
				select_dedent[#select_dedent]:gsub("^" .. min_indent, "")
		end
	else
		-- in block: if indent is in block, remove the part of it that is inside
		-- it for select_dedent.
		if #min_indent > start_col then
			local indent_in_block = min_indent:sub(start_col, #min_indent)
			for i, line in ipairs(chunks) do
				select_dedent[i] = line:gsub("^" .. indent_in_block, "")
			end
		end
	end

	vim.api.nvim_buf_set_var(0, SELECT_RAW, chunks)
	vim.api.nvim_buf_set_var(0, SELECT_DEDENT, select_dedent)
	vim.api.nvim_buf_set_var(0, TM_SELECT, tm_select)
end

local function pos_equal(p1, p2)
	return p1[1] == p2[1] and p1[2] == p2[2]
end

local function string_wrap(lines, pos)
	local new_lines = vim.deepcopy(lines)
	if #new_lines == 1 and #new_lines[1] == 0 then
		return { "$" .. (pos and tostring(pos) or "{}") }
	end
	new_lines[1] = "${"
		.. (pos and (tostring(pos) .. ":") or "")
		.. new_lines[1]
	new_lines[#new_lines] = new_lines[#new_lines] .. "}"
	return new_lines
end

-- Heuristic to extract the comment style from the commentstring
local _comments_cache = {}
local function buffer_comment_chars()
	local commentstring = vim.bo.commentstring
	if _comments_cache[commentstring] then
		return _comments_cache[commentstring]
	end
	local comments = { "//", "/*", "*/" }
	local placeholder = "%s"
	local index_placeholder = commentstring:find(vim.pesc(placeholder))
	if index_placeholder then
		index_placeholder = index_placeholder - 1
		if index_placeholder + #placeholder == #commentstring then
			comments[1] = vim.trim(commentstring:sub(1, -#placeholder - 1))
		else
			comments[2] = vim.trim(commentstring:sub(1, index_placeholder))
			comments[3] = vim.trim(
				commentstring:sub(index_placeholder + #placeholder + 1, -1)
			)
		end
	end
	_comments_cache[commentstring] = comments
	return comments
end

local function to_line_table(table_or_string)
	local tbl = to_string_table(table_or_string)

	-- split entries at \n.
	local line_table = {}
	for _, str in ipairs(tbl) do
		local split = vim.split(str, "\n", true)
		for i = 1, #split do
			line_table[#line_table + 1] = split[i]
		end
	end

	return line_table
end

local function find_outer_snippet(node)
	while node.parent do
		node = node.parent
	end
	return node
end

local function redirect_filetypes(fts)
	local snippet_fts = {}

	for _, ft in ipairs(fts) do
		vim.list_extend(snippet_fts, session.ft_redirect[ft])
	end

	return snippet_fts
end

local function deduplicate(list)
	vim.validate({ list = { list, "table" } })
	local ret = {}
	local contains = {}
	for _, v in ipairs(list) do
		if not contains[v] then
			table.insert(ret, v)
			contains[v] = true
		end
	end
	return ret
end

local function get_snippet_filetypes()
	local config = require("luasnip.session").config
	local fts = config.ft_func()
	-- add all last.
	table.insert(fts, "all")

	return deduplicate(redirect_filetypes(fts))
end

local function pos_add(p1, p2)
	return { p1[1] + p2[1], p1[2] + p2[2] }
end
local function pos_sub(p1, p2)
	return { p1[1] - p2[1], p1[2] - p2[2] }
end

local function pop_front(list)
	local front = list[1]
	for i = 2, #list do
		list[i - 1] = list[i]
	end
	list[#list] = nil
	return front
end

local function sorted_keys(t)
	local s = {}
	local i = 1
	for k, _ in pairs(t) do
		s[i] = k
		i = i + 1
	end
	table.sort(s)
	return s
end

-- from https://www.lua.org/pil/19.3.html
local function key_sorted_pairs(t)
	local sorted = sorted_keys(t)
	local i = 0
	return function()
		i = i + 1
		if sorted[i] == nil then
			return nil
		else
			return sorted[i], t[sorted[i]], i
		end
	end
end

local function no_region_check_wrap(fn, ...)
	session.jump_active = true
	-- will run on next tick, after autocommands (especially CursorMoved) for this are done.
	vim.schedule(function()
		session.jump_active = false
	end)
	return fn(...)
end

local function id(a)
	return a
end

local function no()
	return false
end

local function yes()
	return true
end

local function reverse_lookup(t)
	local rev = {}
	for k, v in pairs(t) do
		rev[v] = k
	end
	return rev
end

local function nop() end

local function indx_of(t, v)
	for i, value in ipairs(t) do
		if v == value then
			return i
		end
	end
	return nil
end

local function lazy_table(lazy_t, lazy_defs)
	return setmetatable(lazy_t, {
		__index = function(t, k)
			local v = lazy_defs[k]
			if v then
				local v_resolved = v()
				rawset(t, k, v_resolved)
				return v_resolved
			end
			return nil
		end,
	})
end

local function ternary(cond, if_val, else_val)
	if cond == true then
		return if_val
	else
		return else_val
	end
end

return {
	get_cursor_0ind = get_cursor_0ind,
	set_cursor_0ind = set_cursor_0ind,
	move_to_mark = move_to_mark,
	normal_move_on_insert = normal_move_on_insert,
	insert_move_on = insert_move_on,
	any_select = any_select,
	remove_n_before_cur = remove_n_before_cur,
	get_current_line_to_cursor = get_current_line_to_cursor,
	line_chars_before = line_chars_before,
	mark_pos_equal = mark_pos_equal,
	multiline_equal = multiline_equal,
	word_under_cursor = word_under_cursor,
	put = put,
	to_string_table = to_string_table,
	wrap_nodes = wrap_nodes,
	store_selection = store_selection,
	get_selection = get_selection,
	pos_equal = pos_equal,
	dedent = dedent,
	indent = indent,
	expand_tabs = expand_tabs,
	tab_width = tab_width,
	buffer_comment_chars = buffer_comment_chars,
	string_wrap = string_wrap,
	to_line_table = to_line_table,
	find_outer_snippet = find_outer_snippet,
	redirect_filetypes = redirect_filetypes,
	get_snippet_filetypes = get_snippet_filetypes,
	json_decode = vim.json.decode,
	json_encode = vim.json.encode,
	bytecol_to_utfcol = bytecol_to_utfcol,
	pos_sub = pos_sub,
	pos_add = pos_add,
	deduplicate = deduplicate,
	pop_front = pop_front,
	key_sorted_pairs = key_sorted_pairs,
	no_region_check_wrap = no_region_check_wrap,
	id = id,
	no = no,
	yes = yes,
	reverse_lookup = reverse_lookup,
	nop = nop,
	indx_of = indx_of,
	lazy_table = lazy_table,
	ternary = ternary,
	jsregexp = jsregexp_ok and jsregexp,
}
