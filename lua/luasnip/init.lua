local util = require("luasnip.util.util")
local lazy_table = require("luasnip.util.lazy_table")
local types = require("luasnip.util.types")
local node_util = require("luasnip.nodes.util")

local session = require("luasnip.session")
local snippet_collection = require("luasnip.session.snippet_collection")
local Environ = require("luasnip.util.environ")
local extend_decorator = require("luasnip.util.extend_decorator")

local loader = require("luasnip.loaders")

local next_expand = nil
local next_expand_params = nil
local ls
local luasnip_data_dir = vim.fn.stdpath("cache") .. "/luasnip"

local log = require("luasnip.util.log").new("main")

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
local function match_snippet(line, type)
	return snippet_collection.match_snippet(
		line,
		util.get_snippet_filetypes(),
		type
	)
end

-- ft:
-- * string: interpreted as filetype, return corresponding snippets.
-- * nil: return snippets for all filetypes:
-- {
-- 	lua = {...},
-- 	cpp = {...},
-- 	...
-- }
-- opts: optional args, can contain `type`, either "snippets" or "autosnippets".
--
-- return table, may be empty.
local function get_snippets(ft, opts)
	opts = opts or {}

	return snippet_collection.get_snippets(ft, opts.type or "snippets") or {}
end

local function default_snip_info(snip)
	return {
		name = snip.name,
		trigger = snip.trigger,
		description = snip.description,
		wordTrig = snip.wordTrig and true or false,
		regTrig = snip.regTrig and true or false,
	}
end

local function available(snip_info)
	snip_info = snip_info or default_snip_info

	local fts = util.get_snippet_filetypes()
	local res = {}
	for _, ft in ipairs(fts) do
		res[ft] = {}
		for _, snip in ipairs(get_snippets(ft)) do
			if not snip.invalidated then
				table.insert(res[ft], snip_info(snip))
			end
		end
		for _, snip in ipairs(get_snippets(ft, { type = "autosnippets" })) do
			if not snip.invalidated then
				table.insert(res[ft], snip_info(snip))
			end
		end
	end
	return res
end

local unlink_set_adjacent_as_current
local function unlink_set_adjacent_as_current_no_log(snippet)
	-- prefer setting previous/outer insertNode as current node.
	local next_current =
		-- either pick i0 of snippet before, or i(-1) of next snippet.
		snippet.prev.prev or snippet:next_node()
	snippet:remove_from_jumplist()

	if next_current then
		-- if snippet was active before, we need to now set its parent to be no
		-- longer inner_active.
		if
			snippet.parent_node == next_current and next_current.inner_active
		then
			snippet.parent_node:input_leave_children()
		else
			-- set no_move.
			local ok, err = pcall(next_current.input_enter, next_current, true)
			if not ok then
				-- this won't try to set the previously broken snippet as
				-- current, since that link is removed in
				-- `remove_from_jumplist`.
				unlink_set_adjacent_as_current(
					next_current.parent.snippet,
					"Error while setting adjacent snippet as current node: %s",
					err
				)
			end
		end
	end

	session.current_nodes[vim.api.nvim_get_current_buf()] = next_current
end
function unlink_set_adjacent_as_current(snippet, reason, ...)
	log.warn("Removing snippet %s: %s", snippet.trigger, reason:format(...))
	unlink_set_adjacent_as_current_no_log(snippet)
end

local function unlink_current()
	local current = session.current_nodes[vim.api.nvim_get_current_buf()]
	if not current then
		print("No active Snippet")
		return
	end
	unlink_set_adjacent_as_current_no_log(current.parent.snippet)
end

-- return next active node.
local function safe_jump_current(dir, no_move, dry_run)
	local node = session.current_nodes[vim.api.nvim_get_current_buf()]
	if not node then
		return nil
	end

	local ok, res = pcall(node.jump_from, node, dir, no_move, dry_run)
	if ok then
		return res
	else
		local snip = node.parent.snippet

		unlink_set_adjacent_as_current(
			snip,
			"Removing snippet `%s` due to error %s",
			snip.trigger,
			res
		)
		return session.current_nodes[vim.api.nvim_get_current_buf()]
	end
end
local function jump(dir)
	local current = session.current_nodes[vim.api.nvim_get_current_buf()]
	if current then
		session.current_nodes[vim.api.nvim_get_current_buf()] =
			util.no_region_check_wrap(safe_jump_current, dir)
		return true
	else
		return false
	end
end
local function jump_destination(dir)
	-- dry run of jump (+no_move ofc.), only retrieves destination-node.
	return safe_jump_current(dir, true, { active = {} })
end

local function jumpable(dir)
	-- node is jumpable if there is a destination.
	return jump_destination(dir)
		~= session.current_nodes[vim.api.nvim_get_current_buf()]
end

local function expandable()
	next_expand, next_expand_params =
		match_snippet(util.get_current_line_to_cursor(), "snippets")
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
	local ok, snip_begin_pos, snip_end_pos =
		pcall(snippet.mark.pos_begin_end, snippet.mark)
	if not ok then
		-- if there was an error getting the position, the snippets text was
		-- most likely removed, resulting in messed up extmarks -> error.
		-- remove the snippet.
		unlink_set_adjacent_as_current(
			snippet,
			"Error while getting extmark-position: %s",
			snip_begin_pos
		)
		return
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	if pos[1] - 1 >= snip_begin_pos[1] and pos[1] - 1 <= snip_end_pos[1] then
		return true -- cursor not on row inside snippet
	end
end

local function expand_or_locally_jumpable()
	return expandable() or (in_snippet() and jumpable(1))
end

local function locally_jumpable(dir)
	return in_snippet() and jumpable(dir)
end

local function _jump_into_default(snippet)
	return util.no_region_check_wrap(snippet.jump_into, snippet, 1)
end

-- opts.clear_region: table, keys `from` and `to`, both (0,0)-indexed.
local function snip_expand(snippet, opts)
	local snip = snippet:copy()

	opts = opts or {}
	opts.expand_params = opts.expand_params or {}
	-- override with current position if none given.
	opts.pos = opts.pos or util.get_cursor_0ind()
	opts.jump_into_func = opts.jump_into_func or _jump_into_default
	opts.indent = vim.F.if_nil(opts.indent, true)

	snip.trigger = opts.expand_params.trigger or snip.trigger
	snip.captures = opts.expand_params.captures or {}

	local info =
		{ trigger = snip.trigger, captures = snip.captures, pos = opts.pos }
	local env = Environ:new(info)
	Environ:override(env, opts.expand_params.env_override or {})

	local pos_id = vim.api.nvim_buf_set_extmark(
		0,
		session.ns_id,
		opts.pos[1],
		opts.pos[2],
		-- track position between pos[2]-1 and pos[2].
		{ right_gravity = false }
	)

	-- optionally clear text. Text has to be cleared befor jumping into the new
	-- snippet, as the cursor-position can end up in the wrong position (to be
	-- precise the text will be moved, the cursor will stay at the same
	-- position, which is just as bad) if text before the cursor, on the same
	-- line is cleared.
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

	local snip_parent_node = snip:trigger_expand(
		session.current_nodes[vim.api.nvim_get_current_buf()],
		pos_id,
		env,
		opts.indent
	)

	-- jump_into-callback returns new active node.
	session.current_nodes[vim.api.nvim_get_current_buf()] =
		opts.jump_into_func(snip)

	local buf_snippet_roots =
		session.snippet_roots[vim.api.nvim_get_current_buf()]
	if not session.config.keep_roots and #buf_snippet_roots > 1 then
		-- if history is not set, and there is more than one snippet-root,
		-- remove the other one.
		-- The nice thing is: since we maintain that #buf_snippet_roots == 1
		-- whenever outside of this function, we know that if we're here, it's
		-- because this snippet was just inserted into buf_snippet_roots.
		-- Armed with this knowledge, we can just check which of the roots is
		-- this snippet, and remove the other one.
		buf_snippet_roots[buf_snippet_roots[1] == snip and 2 or 1]:remove_from_jumplist()
	end

	-- stores original snippet, it doesn't contain any data from expansion.
	session.last_expand_snip = snippet
	session.last_expand_opts = opts

	-- set last action for vim-repeat.
	-- will silently fail if vim-repeat isn't available.
	-- -1 to disable count.
	vim.cmd([[silent! call repeat#set("\<Plug>luasnip-expand-repeat", -1)]])

	return snip
end

---Find a snippet matching the current cursor-position.
---@param opts table: may contain:
--- - `jump_into_func`: passed through to `snip_expand`.
---@return boolean: whether a snippet was expanded.
local function expand(opts)
	local expand_params
	local snip
	-- find snip via next_expand (set from previous expandable()) or manual matching.
	if next_expand ~= nil then
		snip = next_expand
		expand_params = next_expand_params

		next_expand = nil
		next_expand_params = nil
	else
		snip, expand_params =
			match_snippet(util.get_current_line_to_cursor(), "snippets")
	end
	if snip then
		local jump_into_func = opts and opts.jump_into_func

		local cursor = util.get_cursor_0ind()

		local clear_region = expand_params.clear_region
			or {
				from = {
					cursor[1],
					cursor[2] - #expand_params.trigger,
				},
				to = cursor,
			}

		-- override snip with expanded copy.
		snip = snip_expand(snip, {
			expand_params = expand_params,
			-- clear trigger-text.
			clear_region = clear_region,
			jump_into_func = jump_into_func,
		})

		return true
	end
	return false
end

local function expand_auto()
	local snip, expand_params =
		match_snippet(util.get_current_line_to_cursor(), "autosnippets")
	if snip then
		local cursor = util.get_cursor_0ind()
		local clear_region = expand_params.clear_region
			or {
				from = {
					cursor[1],
					cursor[2] - #expand_params.trigger,
				},
				to = cursor,
			}
		snip = snip_expand(snip, {
			expand_params = expand_params,
			-- clear trigger-text.
			clear_region = clear_region,
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
	-- expand snippet as-is.
	snip_expand(
		ls.parser.parse_snippet(
			"",
			body,
			{ trim_empty = false, dedent = false }
		),
		opts
	)
end

local function choice_active()
	return session.active_choice_nodes[vim.api.nvim_get_current_buf()] ~= nil
end

-- attempts to do some action on the snippet (like change_choice, set_choice),
-- if it fails the snippet is removed and the next snippet becomes the current node.
-- ... is passed to pcall as-is.
local function safe_choice_action(snip, ...)
	local ok, res = pcall(...)
	if ok then
		return res
	else
		-- not very elegant, but this way we don't have a near
		-- re-implementation of unlink_current.
		unlink_set_adjacent_as_current(
			snip,
			"Removing snippet `%s` due to error %s",
			snip.trigger,
			res
		)
		return session.current_nodes[vim.api.nvim_get_current_buf()]
	end
end
local function change_choice(val)
	local active_choice =
		session.active_choice_nodes[vim.api.nvim_get_current_buf()]
	assert(active_choice, "No active choiceNode")
	local new_active = util.no_region_check_wrap(
		safe_choice_action,
		active_choice.parent.snippet,
		active_choice.change_choice,
		active_choice,
		val,
		session.current_nodes[vim.api.nvim_get_current_buf()]
	)
	session.current_nodes[vim.api.nvim_get_current_buf()] = new_active
end

local function set_choice(choice_indx)
	local active_choice =
		session.active_choice_nodes[vim.api.nvim_get_current_buf()]
	assert(active_choice, "No active choiceNode")
	local choice = active_choice.choices[choice_indx]
	assert(choice, "Invalid Choice")
	local new_active = util.no_region_check_wrap(
		safe_choice_action,
		active_choice.parent.snippet,
		active_choice.set_choice,
		active_choice,
		choice,
		session.current_nodes[vim.api.nvim_get_current_buf()]
	)
	session.current_nodes[vim.api.nvim_get_current_buf()] = new_active
end

local function get_current_choices()
	local active_choice =
		session.active_choice_nodes[vim.api.nvim_get_current_buf()]
	assert(active_choice, "No active choiceNode")

	local choice_lines = {}

	active_choice:update_static_all()
	for i, choice in ipairs(active_choice.choices) do
		choice_lines[i] = table.concat(choice:get_docstring(), "\n")
	end

	return choice_lines
end

local function active_update_dependents()
	local active = session.current_nodes[vim.api.nvim_get_current_buf()]
	-- special case for startNode, cannot focus on those (and they can't
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

		local ok, err = pcall(active.update_dependents, active)
		if not ok then
			unlink_set_adjacent_as_current(
				active.parent.snippet,
				"Error while updating dependents for snippet %s due to error %s",
				active.parent.snippet.trigger,
				err
			)
			return
		end

		-- 'restore' orientation of extmarks, may have been changed by some set_text or similar.
		ok, err = pcall(active.focus, active)
		if not ok then
			unlink_set_adjacent_as_current(
				active.parent.snippet,
				"Error while entering node in snippet %s: %s",
				active.parent.snippet.trigger,
				err
			)

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
		-- offset 0.
		vim.loop.fs_read(docstring_cache_fd, cache_size, 0)
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
		-- offset 0.
		vim.loop.fs_read(docstring_cache_fd, cache_size, 0)
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

	-- extmarks_valid checks that
	-- * textnodes that should contain text still do so, and
	-- * that extmarks still fulfill all expectations (should be successive, no gaps, etc.)
	if not snippet:extmarks_valid() then
		unlink_set_adjacent_as_current(
			snippet,
			"Detected deletion of snippet `%s`, removing it",
			snippet.trigger
		)
	end
end

local function exit_out_of_region(node)
	-- if currently jumping via luasnip or no active node:
	if session.jump_active or not node then
		return
	end

	local pos = util.get_cursor_0ind()
	local snippet
	if node.type == types.snippet then
		snippet = node
	else
		snippet = node.parent.snippet
	end

	-- find root-snippet.
	while snippet.parent_node do
		snippet = snippet.parent_node.parent.snippet
	end

	local ok, snip_begin_pos, snip_end_pos =
		pcall(snippet.mark.pos_begin_end, snippet.mark)

	if not ok then
		unlink_set_adjacent_as_current(
			snippet,
			"Error while getting extmark-position: %s",
			snip_begin_pos
		)
		return
	end

	-- stylua: ignore
	-- leave if curser before or behind snippet
	if pos[1] < snip_begin_pos[1] or
		pos[1] > snip_end_pos[1] then

		-- make sure the snippet can safely be entered, since it may have to
		-- be, in `refocus`.
		if not snippet:extmarks_valid() then
			unlink_set_adjacent_as_current(snippet, "Leaving snippet-root due to invalid extmarks.")
			return
		end

		local next_active = snippet.insert_nodes[0]
		-- if there is a snippet nested into the $0, enter its $0 instead,
		-- recursively.
		-- This is to ensure that a jump forward after leaving the region of a
		-- root will jump to the next root, or not result in a jump at all.
		while next_active.inner_first do
			-- make sure next_active is nested into completely intact
			-- snippets, since that is a precondition on the to-node of
			if not next_active.inner_first:extmarks_valid() then
				next_active.inner_first:remove_from_jumplist()
			else
				-- inner_first is always the snippet, not the -1-node.
				next_active = next_active.inner_first.insert_nodes[0]
			end
		end

		node_util.refocus(node, next_active)
		session.current_nodes[vim.api.nvim_get_current_buf()] = next_active
	end
end

-- ft string, extend_ft table of strings.
local function filetype_extend(ft, extend_ft)
	vim.list_extend(session.ft_redirect[ft], extend_ft)
	session.ft_redirect[ft] = util.deduplicate(session.ft_redirect[ft])
end

-- ft string, fts table of strings.
local function filetype_set(ft, fts)
	session.ft_redirect[ft] = util.deduplicate(fts)
end

local function cleanup()
	-- Use this to reload luasnip
	vim.api.nvim_exec_autocmds(
		"User",
		{ pattern = "LuasnipCleanup", modeline = false }
	)
	-- clear all snippets.
	snippet_collection.clear_snippets()
	loader.cleanup()
end

local function refresh_notify(ft)
	snippet_collection.refresh_notify(ft)
end

local function setup_snip_env()
	local combined_table = vim.tbl_extend("force", _G, session.config.snip_env)
	-- TODO: if desired, take into account _G's __index before looking into
	-- snip_env's __index.
	setmetatable(combined_table, getmetatable(session.config.snip_env))

	setfenv(2, combined_table)
end
local function get_snip_env()
	return session.get_snip_env()
end

local function get_id_snippet(id)
	return snippet_collection.get_id_snippet(id)
end

local function add_snippets(ft, snippets, opts)
	-- don't use yet, not available in some neovim-versions.
	--
	-- vim.validate({
	-- 	filetype = { ft, { "string", "nil" } },
	-- 	snippets = { snippets, "table" },
	-- 	opts = { opts, { "table", "nil" } },
	-- })

	opts = opts or {}
	opts.refresh_notify = opts.refresh_notify or true
	-- alternatively, "autosnippets"
	opts.type = opts.type or "snippets"

	-- if ft is nil, snippets already has this format.
	if ft then
		snippets = {
			[ft] = snippets,
		}
	end

	snippet_collection.add_snippets(snippets, opts)

	if opts.refresh_notify then
		for ft_, _ in pairs(snippets) do
			refresh_notify(ft_)
		end
	end
end

local function clean_invalidated(opts)
	opts = opts or {}
	snippet_collection.clean_invalidated(opts)
end

local function activate_node(opts)
	opts = opts or {}
	local pos = opts.pos or util.get_cursor_0ind()
	local strict = vim.F.if_nil(opts.strict, false)
	local select = vim.F.if_nil(opts.select, true)

	-- find tree-node the snippet should be inserted at (could be before another node).
	local _, _, _, node = node_util.snippettree_find_undamaged_node(pos, {
		tree_respect_rgravs = false,
		tree_preference = node_util.binarysearch_preference.inside,
		snippet_mode = "interactive",
	})

	if not node then
		error("No Snippet at that position")
		return
	end

	-- only activate interactive nodes, or nodes that are immediately nested
	-- inside a choiceNode.
	if not node:interactive() then
		if strict then
			error("Refusing to activate a non-interactive node.")
			return
		else
			-- fall back to known insertNode.
			-- snippet.insert_nodes[1] may be preferable, but that is not
			-- certainly an insertNode (and does not even certainly contain an
			-- insertNode, think snippetNode with only textNode).
			-- We could *almost* find the first activateable node by
			-- dry_run-jumping into the snippet, but then we'd also need some
			-- mechanism for setting the active-state of all nodes to false,
			-- which we don't yet have.
			--
			-- Instead, just choose -1-node, and allow jumps from there, which
			-- is much simpler.
			node = node.parent.snippet.prev
		end
	end

	node_util.refocus(
		session.current_nodes[vim.api.nvim_get_current_buf()],
		node
	)
	if select then
		-- input_enter node again, to get highlight and the like.
		-- One side-effect of this is that an event will be execute twice, but I
		-- feel like that is a trade-off worth doing, since it otherwise refocus
		-- would have to be more complicated (or at least, restructured).
		node:input_enter()
	end
	session.current_nodes[vim.api.nvim_get_current_buf()] = node
end

-- make these lazy, such that we don't have to load them before it's really
-- necessary (drives up cost of initial load, otherwise).
-- stylua: ignore
local ls_lazy = {
	s = function() return require("luasnip.nodes.snippet").S end,
	sn = function() return require("luasnip.nodes.snippet").SN end,
	t = function() return require("luasnip.nodes.textNode").T end,
	f = function() return require("luasnip.nodes.functionNode").F end,
	i = function() return require("luasnip.nodes.insertNode").I end,
	c = function() return require("luasnip.nodes.choiceNode").C end,
	d = function() return require("luasnip.nodes.dynamicNode").D end,
	r = function() return require("luasnip.nodes.restoreNode").R end,
	snippet = function() return require("luasnip.nodes.snippet").S end,
	snippet_node = function() return require("luasnip.nodes.snippet").SN end,
	parent_indexer = function() return require("luasnip.nodes.snippet").P end,
	indent_snippet_node = function() return require("luasnip.nodes.snippet").ISN end,
	text_node = function() return require("luasnip.nodes.textNode").T end,
	function_node = function() return require("luasnip.nodes.functionNode").F end,
	insert_node = function() return require("luasnip.nodes.insertNode").I end,
	choice_node = function() return require("luasnip.nodes.choiceNode").C end,
	dynamic_node = function() return require("luasnip.nodes.dynamicNode").D end,
	restore_node = function() return require("luasnip.nodes.restoreNode").R end,
	parser = function() return require("luasnip.util.parser") end,
	config = function() return require("luasnip.config") end,
	multi_snippet = function() return require("luasnip.nodes.multiSnippet").new_multisnippet end,
	snippet_source = function() return require("luasnip.session.snippet_collection.source") end,
	select_keys = function() return require("luasnip.util.select").select_keys end
}

ls = lazy_table({
	expand_or_jumpable = expand_or_jumpable,
	expand_or_locally_jumpable = expand_or_locally_jumpable,
	locally_jumpable = locally_jumpable,
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
	set_choice = set_choice,
	get_current_choices = get_current_choices,
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
	add_snippets = add_snippets,
	get_snippets = get_snippets,
	get_id_snippet = get_id_snippet,
	setup_snip_env = setup_snip_env,
	get_snip_env = get_snip_env,
	clean_invalidated = clean_invalidated,
	get_snippet_filetypes = util.get_snippet_filetypes,
	jump_destination = jump_destination,
	session = session,
	cleanup = cleanup,
	refresh_notify = refresh_notify,
	env_namespace = Environ.env_namespace,
	setup = require("luasnip.config").setup,
	extend_decorator = extend_decorator,
	log = require("luasnip.util.log"),
	activate_node = activate_node,
}, ls_lazy)

return ls
