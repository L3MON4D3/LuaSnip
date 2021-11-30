local snip_mod = require("luasnip.nodes.snippet")
local util = require("luasnip.util.util")
local session = require("luasnip.session")

local next_expand = nil
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

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line, snippet_table)
	local match
	local fts = util.get_snippet_filetypes(vim.bo.filetype)

	-- search filetypes, then "all".
	for _, ft in ipairs(fts) do
		for _, snip in ipairs(snippet_table[ft] or {}) do
			match = snip:matches(line)
			if match then
				return match
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
	local fts = util.get_snippet_filetypes(vim.bo.filetype)
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

local jump_active = false
local function no_region_check_wrap(fn, ...)
	jump_active = true
	-- will run on next tick, after autocommands (especially CursorMoved) for this are done.
	vim.schedule(function()
		jump_active = false
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
		if dir == 1 then
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
	next_expand = match_snippet(util.get_current_line_to_cursor(), ls.snippets)
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

local function expand()
	if next_expand ~= nil then
		no_region_check_wrap(
			next_expand.trigger_expand,
			next_expand,
			session.current_nodes[vim.api.nvim_get_current_buf()]
		)
		next_expand = nil
		return true
	else
		local snip = match_snippet(
			util.get_current_line_to_cursor(),
			ls.snippets
		)
		if snip then
			no_region_check_wrap(
				snip.trigger_expand,
				snip,
				session.current_nodes[vim.api.nvim_get_current_buf()]
			)
			return true
		end
	end
	return false
end

local function expand_auto()
	local snip = match_snippet(
		util.get_current_line_to_cursor(),
		ls.autosnippets
	)
	if snip then
		no_region_check_wrap(
			snip.trigger_expand,
			snip,
			session.current_nodes[vim.api.nvim_get_current_buf()]
		)
	end
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

local function lsp_expand(body)
	local snip = ls.parser.parse_snippet({ trig = "" }, body)
	snip:trigger_expand(session.current_nodes[vim.api.nvim_get_current_buf()])
end

local function choice_active()
	return session.active_choice_node ~= nil
end

local function change_choice(val)
	assert(session.active_choice_node, "No active choiceNode")
	local new_active = no_region_check_wrap(
		session.active_choice_node.change_choice,
		session.active_choice_node,
		val
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
	if active and active.pos ~= -1 then
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
		active.parent:enter_node(active.indx)

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
	local snip_begin_pos, snip_end_pos = snippet.mark:pos_begin_end()
	-- stylua: ignore
	-- leave snippet if empty:
	if snip_begin_pos[1] == snip_end_pos[1] and
	   snip_begin_pos[2] == snip_end_pos[2] then
		snippet:remove_from_jumplist()
		session.current_nodes[vim.api.nvim_get_current_buf()] = snippet.prev.prev
			or snippet.next.next
	end
end

local function exit_out_of_region(node)
	-- if currently jumping via luasnip or no active node:
	if jump_active or not node then
		return
	end

	local pos = util.get_cursor_0ind()
	local snippet = node.parent.snippet
	local snip_begin_pos, snip_end_pos = snippet.mark:pos_begin_end()
	-- stylua: ignore
	-- leave if curser before or behind snippet
	if pos[1] < snip_begin_pos[1] or
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

ls = {
	expand_or_jumpable = expand_or_jumpable,
	expand_or_locally_jumpable = expand_or_locally_jumpable,
	jumpable = jumpable,
	expandable = expandable,
	expand = expand,
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
}

return ls
