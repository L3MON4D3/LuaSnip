local snip_mod = require("luasnip.nodes.snippet")
local util = require("luasnip.util.util")
local session = require("luasnip.session")

local next_expand = nil
local next_expand_params = nil
local ls
local luasnip_data_dir = vim.fn.stdpath("cache") .. "/luasnip"

local function get_active_snip()
	local node = session.current_nodes[vim.api.nvim_get_current_buf()]
	if not node then
		return nil
	end
	while node.parent do
		node = node.parent
	end
	return node
end

-- returns matching snippet (needs to be copied before usage!) and its expand-
-- parameters(trigger and captures). params are returned here because there's
-- no need to recalculate them.
local function match_snippet(line, snippet_table)
	local expand_params
	local fts = util.get_snippet_filetypes()

	-- search filetypes, then "all".
	for _, ft in ipairs(fts) do
		for _, snip in ipairs(snippet_table[ft] or {}) do
			expand_params = snip:matches(line)
			if expand_params then
				-- return matching snippet and table with expand-parameters.
				return snip, expand_params
			end
		end
	end
	return nil
end

local function get_context(snip)
	return {
		name = snip.name,
		trigger = snip.trigger,
		description = snip.dscr,
		wordTrig = snip.wordTrig and true or false,
		regTrig = snip.regTrig and true or false,
	}
end

local function available()
	local fts = util.get_snippet_filetypes()
	local res = {}
	for _, ft in ipairs(fts) do
		res[ft] = {}
		for _, snippet_table in pairs({ ls.snippets, ls.autosnippets }) do
			if snippet_table[ft] then
				for _, snip in ipairs(snippet_table[ft]) do
					table.insert(res[ft], get_context(snip))
				end
			end
		end
	end
	return res
end

local function no_region_check_wrap(fn, ...)
	session.jump_active = true
	-- will run on next tick, after autocommands (especially CursorMoved) for this are done.
	vim.schedule(function()
		session.jump_active = false
	end)
	return fn(...)
end

local function safe_jump(node, dir, no_move)
	if not node then
		return nil
	end

	local ok, res = pcall(node.jump_from, node, dir, no_move)
	if ok then
		return res
	else
		local snip = node.parent.snippet
		snip:remove_from_jumplist()
		-- dir==1: try jumping into next snippet, then prev
		-- dir==-1: try jumping into prev snippet, then next
		if not dir or dir == 1 then
			return safe_jump(
				snip.next.next or snip.prev.prev,
				snip.next.next and 1 or -1,
				no_move
			)
		else
			return safe_jump(
				snip.prev.prev or snip.next.next,
				snip.prev.prev and -1 or 1,
				no_move
			)
		end
	end
end
local function jump(dir)
	local current = session.current_nodes[vim.api.nvim_get_current_buf()]
	if current then
		session.current_nodes[vim.api.nvim_get_current_buf()] =
			no_region_check_wrap(
				safe_jump,
				current,
				dir
			)
		return true
	else
		return false
	end
end

local function jumpable(dir)
	local node = session.current_nodes[vim.api.nvim_get_current_buf()]
	return (node ~= nil and node:jumpable(dir))
end

local function expandable()
	next_expand, next_expand_params = match_snippet(
		util.get_current_line_to_cursor(),
		ls.snippets
	)
	return next_expand ~= nil
end

local function expand_or_jumpable()
	return expandable() or jumpable(1)
end

local function in_snippet()
	-- check if the cursor on a row inside a snippet.
	local node = session.current_nodes[vim.api.nvim_get_current_buf()]
	if not node then
		return false
	end
	local snippet = node.parent.snippet
	local snip_begin_pos, snip_end_pos = snippet.mark:pos_begin_end()
	local pos = vim.api.nvim_win_get_cursor(0)
	if pos[1] - 1 >= snip_begin_pos[1] and pos[1] - 1 <= snip_end_pos[1] then
		return true -- cursor not on row inside snippet
	end
end

local function expand_or_locally_jumpable()
	return expandable() or (in_snippet() and jumpable())
end

-- opts.clear_region: table, keys `from` and `to`, both (0,0)-indexed.
local function snip_expand(snippet, opts)
	local snip = snippet:copy()

	opts = opts or {}
	opts.expand_params = opts.expand_params or {}
	-- override with current position if none given.
	opts.pos = opts.pos or util.get_cursor_0ind()

	snip.trigger = opts.expand_params.trigger or snip.trigger
	snip.captures = opts.expand_params.captures or {}

	snip:trigger_expand(
		session.current_nodes[vim.api.nvim_get_current_buf()],
		opts.pos
	)

	-- optionally clear text. Text has to be cleared befor jumping into the new
	-- snippet, as the cursor-position can end up in the wrong position (to be
	-- precise the text will be moved, the cursor will stay at the same position,
	-- which is just as bad) if text before the cursor, on the same line is cleared.
	if opts.clear_region then
		vim.api.nvim_buf_set_text(
			0,
			opts.clear_region.from[1],
			opts.clear_region.from[2],
			opts.clear_region.to[1],
			opts.clear_region.to[2],
			{ "" }
		)
	end

	local current_buf = vim.api.nvim_get_current_buf()

	if session.current_nodes[current_buf] then
		local current_node = session.current_nodes[current_buf]
		if current_node.pos > 0 then
			-- snippet is nested, notify current insertNode about expansion.
			current_node.inner_active = true
		else
			-- snippet was expanded behind a previously active one, leave the i(0)
			-- properly (and remove the snippet on error).
			if not pcall(current_node.input_leave, current_node) then
				current_node.parent.snippet:remove_from_jumplist()
			end
		end
	end

	session.current_nodes[vim.api.nvim_get_current_buf()] =
		no_region_check_wrap(
			snip.jump_into,
			snip,
			1
		)

	-- stores original snippet, it doesn't contain any data from expansion.
	session.last_expand_snip = snippet
	session.last_expand_opts = opts

	-- set last action for vim-repeat.
	-- will silently fail if vim-repeat isn't available.
	-- -1 to disable count.
	vim.cmd([[silent! call repeat#set("\<Plug>luasnip-expand-repeat", -1)]])

	return snip
end

local function expand()
	local expand_params
	local snip
	-- find snip via next_expand (set from previous expandable()) or manual matching.
	if next_expand ~= nil then
		snip = next_expand
		expand_params = next_expand_params
		next_expand = nil
		next_expand_params = nil
	else
		snip, expand_params = match_snippet(
			util.get_current_line_to_cursor(),
			ls.snippets
		)
	end
	if snip then
		local cursor = util.get_cursor_0ind()
		-- override snip with expanded copy.
		snip = snip_expand(snip, {
			expand_params = expand_params,
			-- clear trigger-text.
			clear_region = {
				from = {
					cursor[1],
					cursor[2] - #expand_params.trigger,
				},
				to = cursor,
			},
		})
		return true
	end
	return false
end

local function expand_auto()
	local snip, expand_params = match_snippet(
		util.get_current_line_to_cursor(),
		ls.autosnippets
	)
	if snip then
		local cursor = util.get_cursor_0ind()
		snip = snip_expand(snip, {
			expand_params = expand_params,
			-- clear trigger-text.
			clear_region = {
				from = {
					cursor[1],
					cursor[2] - #expand_params.trigger,
				},
				to = cursor,
			},
		})
	end
end

local function expand_repeat()
	-- prevent clearing text with repeated expand.
	session.last_expand_opts.clear_region = nil
	session.last_expand_opts.pos = nil

	snip_expand(session.last_expand_snip, session.last_expand_opts)
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	if expand() then
		return true
	end
	if jump(1) then
		return true
	end
	return false
end

local function lsp_expand(body, opts)
	snip_expand(ls.parser.parse_snippet("", body), opts)
end

local function choice_active()
	return session.active_choice_node ~= nil
end

local function change_choice(val)
	assert(session.active_choice_node, "No active choiceNode")
	local new_active = no_region_check_wrap(
		session.active_choice_node.change_choice,
		session.active_choice_node,
		val,
		session.current_nodes[vim.api.nvim_get_current_buf()]
	)
	session.current_nodes[vim.api.nvim_get_current_buf()] = new_active
end

local function unlink_current()
	local node = session.current_nodes[vim.api.nvim_get_current_buf()]
	if not node then
		print("No active Snippet")
		return
	end
	local user_expanded_snip = node.parent
	-- find 'outer' snippet.
	while user_expanded_snip.parent do
		user_expanded_snip = user_expanded_snip.parent
	end

	user_expanded_snip:remove_from_jumplist()
	-- prefer setting previous/outer insertNode as current node.
	session.current_nodes[vim.api.nvim_get_current_buf()] = user_expanded_snip.prev.prev
		or user_expanded_snip.next.next
end

local function active_update_dependents()
	local active = session.current_nodes[vim.api.nvim_get_current_buf()]
	-- special case for startNode, cannot enter_node on those (and they can't
	-- have dependents)
	-- don't update if a jump/change_choice is in progress.
	if not session.jump_active and active and active.pos > 0 then
		-- Save cursor-pos to restore later.
		local cur = util.get_cursor_0ind()
		local cur_mark = vim.api.nvim_buf_set_extmark(
			0,
			session.ns_id,
			cur[1],
			cur[2],
			{ right_gravity = false }
		)

		local ok = pcall(active.update_dependents, active)
		if not ok then
			unlink_current()
			return
		end

		-- 'restore' orientation of extmarks, may have been changed by some set_text or similar.
		if not pcall(active.parent.enter_node, active.parent, active.indx) then
			unlink_current()
			return
		end

		-- Don't account for utf, nvim_win_set_cursor doesn't either.
		cur = vim.api.nvim_buf_get_extmark_by_id(
			0,
			session.ns_id,
			cur_mark,
			{ details = false }
		)
		util.set_cursor_0ind(cur)
	end
end

local function store_snippet_docstrings(snippet_table)
	-- ensure the directory exists.
	-- 493 = 0755
	vim.loop.fs_mkdir(luasnip_data_dir, 493)

	-- fs_open() with w+ creates the file if nonexistent.
	local docstring_cache_fd = vim.loop.fs_open(
		luasnip_data_dir .. "/docstrings.json",
		"w+",
		-- 420 = 0644
		420
	)

	-- get size for fs_read()
	local cache_size = vim.loop.fs_fstat(docstring_cache_fd).size
	local file_could_be_read, docstrings = pcall(
		util.json_decode,
		vim.loop.fs_read(docstring_cache_fd, cache_size)
	)
	docstrings = file_could_be_read and docstrings or {}

	for ft, snippets in pairs(snippet_table) do
		if not docstrings[ft] then
			docstrings[ft] = {}
		end
		for _, snippet in ipairs(snippets) do
			docstrings[ft][snippet.trigger] = snippet:get_docstring()
		end
	end

	vim.loop.fs_write(docstring_cache_fd, util.json_encode(docstrings))
end

local function load_snippet_docstrings(snippet_table)
	-- ensure the directory exists.
	-- 493 = 0755
	vim.loop.fs_mkdir(luasnip_data_dir, 493)

	-- fs_open() with "r" returns nil if the file doesn't exist.
	local docstring_cache_fd = vim.loop.fs_open(
		luasnip_data_dir .. "/docstrings.json",
		"r",
		-- 420 = 0644
		420
	)

	if not docstring_cache_fd then
		error("Cached docstrings could not be read!")
		return
	end
	-- get size for fs_read()
	local cache_size = vim.loop.fs_fstat(docstring_cache_fd).size
	local docstrings = util.json_decode(
		vim.loop.fs_read(docstring_cache_fd, cache_size)
	)

	for ft, snippets in pairs(snippet_table) do
		-- skip if fieltype not in cache.
		if docstrings[ft] then
			for _, snippet in ipairs(snippets) do
				-- only set if it hasn't been set already.
				if not snippet.docstring then
					snippet.docstring = docstrings[ft][snippet.trigger]
				end
			end
		end
	end
end

local function unlink_current_if_deleted()
	local node = session.current_nodes[vim.api.nvim_get_current_buf()]
	if not node then
		return
	end
	local snippet = node.parent.snippet
	local ok, snip_begin_pos, snip_end_pos = pcall(
		snippet.mark.pos_begin_end_raw,
		snippet.mark
	)
	-- stylua: ignore
	-- leave snippet if empty:
	if not ok or
		-- either exactly the same position...
		(snip_begin_pos[1] == snip_end_pos[1] and
		 snip_begin_pos[2] == snip_end_pos[2]) or
		-- or the end-mark is one line below and there is no text between them.
		-- (this can happen when deleting linewise-visual or via `dd`)
		(snip_begin_pos[1]+1 == snip_end_pos[1] and
		 snip_end_pos[2] == 0 and
		 #vim.api.nvim_buf_get_lines(0, snip_begin_pos[1], snip_begin_pos[1]+1, true)[1] == 0) then
		snippet:remove_from_jumplist()
		session.current_nodes[vim.api.nvim_get_current_buf()] = snippet.prev.prev
			or snippet.next.next
	end
end

local function exit_out_of_region(node)
	-- if currently jumping via luasnip or no active node:
	if session.jump_active or not node then
		return
	end

	local pos = util.get_cursor_0ind()
	local snippet = node.parent.snippet
	local ok, snip_begin_pos, snip_end_pos = pcall(
		snippet.mark.pos_begin_end,
		snippet.mark
	)
	-- stylua: ignore
	-- leave if curser before or behind snippet
	if not ok or
		pos[1] < snip_begin_pos[1] or
		pos[1] > snip_end_pos[1] then
		-- jump as long as the 0-node of the snippet hasn't been reached.
		-- check for nil; if history is not set, the jump to snippet.next
		-- returns nil.
		while node and node ~= snippet.next do
			local ok
			-- set no_move.
			ok, node = pcall(node.jump_from, node, 1, true)
			if not ok then
				snippet:remove_from_jumplist()
				-- may be nil, checked later.
				node = snippet.next
				break
			end
		end
		session.current_nodes[vim.api.nvim_get_current_buf()] = node

		-- also check next snippet.
		if node and node.next then
			if exit_out_of_region(node.next) then
				node:input_leave(1, true)
			end
		end
		return true
	end
	return false
end

-- ft string, extend_ft table of strings.
local function filetype_extend(ft, extend_ft)
	vim.list_extend(session.ft_redirect[ft], extend_ft)
end

-- ft string, fts table of strings.
local function filetype_set(ft, fts)
	session.ft_redirect[ft] = fts
end

local function cleanup()
	-- Use this to reload luasnip
	vim.cmd([[doautocmd User LuasnipCleanup]])
end

local function refresh_notify(ft)
	vim.validate({
		filetype = { ft, "string" },
	})
	session.latest_load_ft = ft
	vim.cmd([[doautocmd User LuasnipSnippetsAdded]])
end

ls = {
	expand_or_jumpable = expand_or_jumpable,
	expand_or_locally_jumpable = expand_or_locally_jumpable,
	jumpable = jumpable,
	expandable = expandable,
	in_snippet = in_snippet,
	expand = expand,
	snip_expand = snip_expand,
	expand_repeat = expand_repeat,
	expand_auto = expand_auto,
	expand_or_jump = expand_or_jump,
	jump = jump,
	get_active_snip = get_active_snip,
	choice_active = choice_active,
	change_choice = change_choice,
	unlink_current = unlink_current,
	lsp_expand = lsp_expand,
	active_update_dependents = active_update_dependents,
	available = available,
	exit_out_of_region = exit_out_of_region,
	load_snippet_docstrings = load_snippet_docstrings,
	store_snippet_docstrings = store_snippet_docstrings,
	unlink_current_if_deleted = unlink_current_if_deleted,
	filetype_extend = filetype_extend,
	filetype_set = filetype_set,
	s = snip_mod.S,
	sn = snip_mod.SN,
	t = require("luasnip.nodes.textNode").T,
	f = require("luasnip.nodes.functionNode").F,
	i = require("luasnip.nodes.insertNode").I,
	c = require("luasnip.nodes.choiceNode").C,
	d = require("luasnip.nodes.dynamicNode").D,
	r = require("luasnip.nodes.restoreNode").R,
	snippet = snip_mod.S,
	snippet_node = snip_mod.SN,
	parent_indexer = snip_mod.P,
	indent_snippet_node = snip_mod.ISN,
	text_node = require("luasnip.nodes.textNode").T,
	function_node = require("luasnip.nodes.functionNode").F,
	insert_node = require("luasnip.nodes.insertNode").I,
	choice_node = require("luasnip.nodes.choiceNode").C,
	dynamic_node = require("luasnip.nodes.dynamicNode").D,
	restore_node = require("luasnip.nodes.restoreNode").R,
	parser = require("luasnip.util.parser"),
	config = require("luasnip.config"),
	snippets = { all = {} },
	autosnippets = { all = {} },
	session = session,
	cleanup = cleanup,
	refresh_notify = refresh_notify,
}

return ls
