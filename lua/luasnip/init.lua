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

---@class LuaSnip.API
local API = {}

--- Get the currently active snippet.
---@return LuaSnip.Snippet? _ The active snippet if one exists, or `nil`.
function API.get_active_snip()
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

---@class LuaSnip.Opts.GetSnippets
---@field type? "snippets"|"autosnippets" Whether to get snippets or
---  autosnippets. Defaults to "snippets".

--- Retrieve snippets from luasnip.
---@param ft? string Filetype, if not given returns snippets for all filetypes.
---@param opts? LuaSnip.Opts.GetSnippets Optional arguments.
---@return LuaSnip.Snippet[]|{[string]: LuaSnip.Snippet[]} _ Flat array when
---  `ft` is non-nil, otherwise a table mapping filetypes to snippets.
function API.get_snippets(ft, opts)
	opts = opts or {}

	return snippet_collection.get_snippets(ft, opts.type or "snippets") or {}
end

---@param snip LuaSnip.Snippet
---@return any
local function default_snip_info(snip)
	return {
		name = snip.name,
		trigger = snip.trigger,
		description = snip.description,
		wordTrig = snip.wordTrig and true or false,
		regTrig = snip.regTrig and true or false,
	}
end

--- Retrieve information about snippets available in the current file/at the
--- current position (in case treesitter-based filetypes are enabled).
---
---@generic T
---@param snip_info? (fun(LuaSnip.Snippet): T) Optionally pass a function that,
---  given a snippet, returns the data that is returned by this function in the
---  snippets' stead.
---  By default, this function is
---  ```lua
---  function(snip)
---      return {
---          name = snip.name,
---          trigger = snip.trigger,
---          description = snip.description,
---          wordTrig = snip.wordTrig and true or false,
---          regTrig = snip.regTrig and true or false,
---      }
---  end
---  ```
---@return {[string]: T[]} _ Table mapping filetypes to list of data returned by
---  snip_info function.
function API.available(snip_info)
	snip_info = snip_info or default_snip_info

	local fts = util.get_snippet_filetypes()
	local res = {}
	for _, ft in ipairs(fts) do
		res[ft] = {}
		for _, snip in ipairs(API.get_snippets(ft)) do
			if not snip.invalidated then
				table.insert(res[ft], snip_info(snip))
			end
		end
		for _, snip in ipairs(API.get_snippets(ft, { type = "autosnippets" })) do
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

--- Removes the current snippet from the jumplist (useful if LuaSnip fails to
--- automatically detect e.g. deletion of a snippet) and sets the current node
--- behind the snippet, or, if not possible, before it.
function API.unlink_current()
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

--- Jump forwards or backwards
---@param dir 1|-1 Jump forward for 1, backward for -1.
---@return boolean _ `true` if a jump was performed, `false` otherwise.
function API.jump(dir)
	local current = session.current_nodes[vim.api.nvim_get_current_buf()]
	if current then
		local next_node = util.no_region_check_wrap(safe_jump_current, dir)
		if next_node == nil then
			session.current_nodes[vim.api.nvim_get_current_buf()] = nil
			return true
		end
		if session.config.exit_roots then
			if next_node.pos == 0 and next_node.parent.parent_node == nil then
				session.current_nodes[vim.api.nvim_get_current_buf()] = nil
				return true
			end
		end
		session.current_nodes[vim.api.nvim_get_current_buf()] = next_node
		return true
	else
		return false
	end
end

--- Find the node the next jump will end up at. This will not work always,
--- because we will not update the node before jumping, so if the jump would
--- e.g. insert a new node between this node and its pre-update jump target,
--- this would not be registered.
--- Thus, it currently only works for simple cases.
---@param dir 1|-1 `1`: find the next node, `-1`: find the previous node.
---@return LuaSnip.Node _ The destination node.
function API.jump_destination(dir)
	-- dry run of jump (+no_move ofc.), only retrieves destination-node.
	return safe_jump_current(dir, true, { active = {} })
end

--- Return whether jumping forwards or backwards will actually jump, or if
--- there is no node in that direction.
---@param dir 1|-1 `1` forward, `-1` backward.
---@return boolean
function API.jumpable(dir)
	-- node is jumpable if there is a destination.
	return API.jump_destination(dir)
		~= session.current_nodes[vim.api.nvim_get_current_buf()]
end

--- Return whether there is an expandable snippet at the current cursor
--- position. Does not consider autosnippets since those would already be
--- expanded at this point.
---@return boolean
function API.expandable()
	next_expand, next_expand_params =
		match_snippet(util.get_current_line_to_cursor(), "snippets")
	return next_expand ~= nil
end

--- Return whether it's possible to expand a snippet at the current
--- cursor-position, or whether it's possible to jump forward from the current
--- node.
---@return boolean
function API.expand_or_jumpable()
	return API.expandable() or API.jumpable(1)
end

--- Determine whether the cursor is within a snippet.
---@return boolean
function API.in_snippet()
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
		return false
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	if pos[1] - 1 >= snip_begin_pos[1] and pos[1] - 1 <= snip_end_pos[1] then
		return true -- cursor not on row inside snippet
	end
	return false
end

--- Return whether a snippet can be expanded at the current cursor position, or
--- whether the cursor is inside a snippet and the current node can be jumped
--- forward from.
---@return boolean
function API.expand_or_locally_jumpable()
	return API.expandable() or (API.in_snippet() and API.jumpable(1))
end

--- Return whether the cursor is inside a snippet and the current node can be
--- jumped forward from.
---@param dir 1|-1 Test jumping forwards/backwards.
---@return boolean
function API.locally_jumpable(dir)
	return API.in_snippet() and API.jumpable(dir)
end

local function _jump_into_default(snippet)
	return util.no_region_check_wrap(snippet.jump_into, snippet, 1)
end

-- opts.clear_region: table, keys `from` and `to`, both (0,0)-indexed.

---@class LuaSnip.Opts.SnipExpandExpandParams
---@field trigger? string What to set as the expanded snippets' trigger
---  (Defaults to `snip.trigger`).
---@field captures? string[] Set as the expanded snippets' captures
---  (Defaults to `{}`).
---@field env_override? {[string]: string} Set or override environment
---  variables of the expanded snippet (Defaults to `{}`).

---@class LuaSnip.Opts.Expand
---@field jump_into_func? (fun(snip: LuaSnip.Snippet): LuaSnip.Node)
---  Callback responsible for jumping into the snippet. The returned node is
---  set as the new active node, i.e. it is the origin of the next jump.
---  The default is basically this:
---  ```lua
---  function(snip)
---      -- jump_into set the placeholder of the snippet, 1
---      -- to jump forwards.
---      return snip:jump_into(1)
---  end
---  ```
---  while this can be used to insert the snippet and immediately move the cursor
---  at the `i(0)`:
---  ```lua
---  function(snip)
---      return snip.insert_nodes[0]
---  end
---  ```

--This can also use `jump_into_func`.
---@class LuaSnip.Opts.SnipExpand: LuaSnip.Opts.Expand
---
---@field clear_region? LuaSnip.BufferRegion A region of text to clear after
---  populating env-variables, but before jumping into `snip`. If `nil`, no
---  clearing is performed.
---  Being able to remove text at this point is useful as clearing before calling
---  this function would populate `TM_CURRENT_LINE` and `TM_CURRENT_WORD` with
---  wrong values (they would miss the snippet trigger).
---  The actual values used for clearing are `region.from` and `region.to`, both
---  (0,0)-indexed byte-positions in the buffer.
---
---@field expand_params? LuaSnip.Opts.SnipExpandExpandParams Override various
---  fields of the expanded snippet. Don't override anything by default.
---  This is useful for manually expanding snippets where the trigger passed
---  via `trig` is not the text triggering the snippet, or those which expect
---  `captures` (basically, snippets with a non-plaintext `trigEngine`).
---
---  One Example:
---  ```lua
---  snip_expand(snip, {
---      trigger = "override_trigger",
---      captures = {"first capture", "second capture"},
---      env_override = { this_key = "some value", other_key = {"multiple", "lines"}, TM_FILENAME = "some_other_filename.lua" }
---  })
---  ```
---
---@field pos? [integer, integer] Position at which the snippet should be
---  inserted. Pass as `(row,col)`, both 0-based, the `col` given in bytes.
---
---@field indent? boolean Whether to prepend the current lines' indent to all
---  lines of the snippet. (Defaults to `true`)
---  Turning this off is a good idea when a LSP server already takes indents into
---  consideration. In such cases, LuaSnip should not add additional indents. If
---  you are using `nvim-cmp`, this could be used as follows:
---  ```lua
---  require("cmp").setup {
---      snippet = {
---          expand = function(args)
---              local indent_nodes = true
---              if vim.api.nvim_get_option_value("filetype", { buf = 0 }) == "dart" then
---                  indent_nodes = false
---              end
---              require("luasnip").lsp_expand(args.body, {
---                  indent = indent_nodes,
---              })
---          end,
---      },
---  }
---  ```

--- Expand a snippet in the current buffer.
---@param snippet LuaSnip.Snippet The snippet.
---@param opts? LuaSnip.Opts.SnipExpand Optional additional arguments.
---@return LuaSnip.ExpandedSnippet _ The snippet that was inserted into the
---  buffer.
function API.snip_expand(snippet, opts)
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

--- Find a snippet whose trigger matches the text before the cursor and expand
--- it.
---@param opts? LuaSnip.Opts.Expand Subset of opts accepted by `snip_expand`.
---@return boolean _ Whether a snippet was expanded.
function API.expand(opts)
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
		assert(expand_params) -- hint lsp type checker
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
		snip = API.snip_expand(snip, {
			expand_params = expand_params,
			-- clear trigger-text.
			clear_region = clear_region,
			jump_into_func = jump_into_func,
		})

		return true
	end
	return false
end

--- Find an autosnippet matching the text at the cursor-position and expand it.
function API.expand_auto()
	local snip, expand_params =
		match_snippet(util.get_current_line_to_cursor(), "autosnippets")
	if snip then
		assert(expand_params) -- hint lsp type checker
		local cursor = util.get_cursor_0ind()
		local clear_region = expand_params.clear_region
			or {
				from = {
					cursor[1],
					cursor[2] - #expand_params.trigger,
				},
				to = cursor,
			}
		snip = API.snip_expand(snip, {
			expand_params = expand_params,
			-- clear trigger-text.
			clear_region = clear_region,
		})
	end
end

--- Repeat the last performed `snip_expand`. Useful for dot-repeat.
function API.expand_repeat()
	-- prevent clearing text with repeated expand.
	session.last_expand_opts.clear_region = nil
	session.last_expand_opts.pos = nil

	API.snip_expand(session.last_expand_snip, session.last_expand_opts)
end

--- Expand at the cursor, or jump forward.
---@return boolean _ Whether an action was performed.
function API.expand_or_jump()
	if API.expand() then
		return true
	end
	if API.jump(1) then
		return true
	end
	return false
end

--- Expand a snippet specified in lsp-style.
---@param body string A string specifying a lsp-snippet,
---  e.g. `"[${1:text}](${2:url})"`
---@param opts? LuaSnip.Opts.SnipExpand Optional args passed through to
---  `snip_expand`.
function API.lsp_expand(body, opts)
	-- expand snippet as-is.
	API.snip_expand(
		ls.parser.parse_snippet(
			"",
			body,
			{ trim_empty = false, dedent = false }
		),
		opts
	)
end

--- Return whether the current node is inside a choiceNode.
---@return boolean
function API.choice_active()
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

--- Change the currently active choice.
---@param val 1|-1 Move one choice forward or backward.
function API.change_choice(val)
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

--- Set the currently active choice.
---@param choice_indx integer Index of the choice to switch to.
function API.set_choice(choice_indx)
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

--- Get a string-representation of all the current choiceNode's choices.
---@return string[] _ \n-concatenated lines of every choice.
function API.get_current_choices()
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

--- Update all nodes that depend on the currently-active node.
function API.active_update_dependents()
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

--- Generate and store the docstrings for a list of snippets as generated by
--- `get_snippets()`.
--- The docstrings are stored at `stdpath("cache") .. "/luasnip/docstrings.json"`,
--- are indexed by their trigger, and should be updated once any snippet
--- changes.
---@param snippet_table {[string]: LuaSnip.Snippet[]} A table mapping some
---  keys to lists of snippets (keys are most likely filetypes).
function API.store_snippet_docstrings(snippet_table)
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

--- Provide all passed snippets with a previously-stored (via
--- `store_snippet_docstrings`) docstring. This prevents a somewhat costly
--- computation which is performed whenever a snippets' docstring is first
--- retrieved, but may cause larger delays when `snippet_table` contains many of
--- snippets.
--- Utilize this function by calling
--- `ls.store_snippet_docstrings(ls.get_snippets())` whenever snippets are
--- modified, and `ls.load_snippet_docstrings(ls.get_snippets())` on startup.
---@param snippet_table {[string]: LuaSnip.Snippet[]} List of snippets, should
---  contain the same keys (filetypes) as the table that was passed to
---  `store_snippet_docstrings`. Again, most likely the result of
---  `get_snippets`.
function API.load_snippet_docstrings(snippet_table)
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

--- Checks whether (part of) the current snippet's text was deleted, and removes
--- it from the jumplist if it was (it cannot be jumped back into).
function API.unlink_current_if_deleted()
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

--- Checks whether the cursor is still within the range of the root-snippet
--- `node` belongs to. If yes, no change occurs; if no, the root-snippet is
--- exited and its `i(0)` will be the new active node.
--- If a jump causes an error (happens mostly because the text of a snippet was
--- deleted), the snippet is removed from the jumplist and the current node set
--- to the end/beginning of the next/previous snippet.
---@param node LuaSnip.Node
function API.exit_out_of_region(node)
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

--- Add `extend_ft` filetype to inherit its snippets from `ft`.
---
--- Example:
--- ```lua
--- ls.filetype_extend("sh", {"zsh"})
--- ls.filetype_extend("sh", {"bash"})
--- ```
--- This makes all `sh` snippets available in `sh`/`zsh`/`bash` buffers.
---
---@param ft string
---@param extend_ft string[]
function API.filetype_extend(ft, extend_ft)
	vim.list_extend(session.ft_redirect[ft], extend_ft)
	session.ft_redirect[ft] = util.deduplicate(session.ft_redirect[ft])
end

--- Set `fts` filetypes as inheriting their snippets from `ft`.
---
--- Example:
--- ```lua
--- ls.filetype_set("sh", {"sh", "zsh", "bash"})
--- ```
--- This makes all `sh` snippets available in `sh`/`zsh`/`bash` buffers.
---
---@param ft string
---@param fts string[]
function API.filetype_set(ft, fts)
	session.ft_redirect[ft] = util.deduplicate(fts)
end

--- Clear all loaded snippets. Also sends the `User LuasnipCleanup`
--- autocommand, so plugins that depend on luasnip's snippet-state can clean up
--- their now-outdated state.
function API.cleanup()
	-- Use this to reload luasnip
	vim.api.nvim_exec_autocmds(
		"User",
		{ pattern = "LuasnipCleanup", modeline = false }
	)
	-- clear all snippets.
	snippet_collection.clear_snippets()
	loader.cleanup()
end

--- Trigger the `User LuasnipSnippetsAdded` autocommand that signifies to other
--- plugins that a filetype has received new snippets.
---
---@param ft string The filetype that has new snippets.
---  Code that listens to this event can retrieve this filetype from
---  `require("luasnip").session.latest_load_ft`.
function API.refresh_notify(ft)
	snippet_collection.refresh_notify(ft)
end

--- Injects the fields defined in `snip_env`, in `setup`, into the callers
--- global environment.
---
--- This means that variables like `s`, `sn`, `i`, `t`, ... (by default) work,
--- and are useful for quickly testing snippets in a buffer:
--- ```lua
--- local ls = require("luasnip")
--- ls.setup_snip_env()
---
--- ls.add_snippets("all", {
---     s("choicetest", {
---         t":", c(1, {
---             t("asdf", {node_ext_opts = {active = { virt_text = {{"asdf", "Comment"}} }}}),
---             t("qwer", {node_ext_opts = {active = { virt_text = {{"qwer", "Comment"}} }}}),
---         })
---     })
--- }, { key = "3d9cd211-c8df-4270-915e-bf48a0be8a79" })
--- ```
--- where the `key` makes it easy to reload the snippets on changes, since the
--- previously registered snippets will be replaced when the buffer is re-sourced.
function API.setup_snip_env()
	local combined_table = vim.tbl_extend("force", _G, session.config.snip_env)
	-- TODO: if desired, take into account _G's __index before looking into
	-- snip_env's __index.
	setmetatable(combined_table, getmetatable(session.config.snip_env))

	setfenv(2, combined_table)
end

--- Return the currently active snip_env.
---@return table
function API.get_snip_env()
	return session.get_snip_env()
end

--- Get the snippet corresponding to some id.
---@param id LuaSnip.SnippetID
---@return LuaSnip.Snippet
function API.get_id_snippet(id)
	return snippet_collection.get_id_snippet(id)
end

---@class LuaSnip.Opts.AddSnippets
---
---@field type? "snippets"|"autosnippets" What to set `snippetType` to if it is
---  not defined for an individual snippet. Defaults to `"snippets"`.
---
---@field key? string This key uniquely identifies this call to `add_snippets`.
---  If another call has the same `key`, the snippets added in this call will be
---  removed.
---  This is useful for reloading snippets once they are updated.
---
---@field override_priority? integer Override the priority of individual
---  snippets.
---
---@field default_priority? integer Priority of snippets where `priority` is not
---  already set. (Defaults to 1000)
---
---@field refresh_notify? boolean Whether to call `refresh_notify` once the
---  snippets are added. (Defaults to true)

--- Add snippets to luasnip's snippet-collection.
---
--- NOTE: Calls `refresh_notify` as needed if enabled via `opts.refresh_notify`.
---
---@param ft? string The filetype to add the snippets to, or nil if the filetype
---  is specified in `snippets`.
---
---@param snippets LuaSnip.Addable[]|{[string]: LuaSnip.Addable[]} If `ft` is
---  nil a table mapping a filetype to a list of snippets, otherwise a flat
---  table of snippets.
---  `LuaSnip.Addable` are objects created by e.g. the functions `s`, `ms`, or
---  `sp`.
---
---@param opts LuaSnip.Opts.AddSnippets? Optional arguments.
function API.add_snippets(ft, snippets, opts)
	util.validate("filetype", ft, { "string", "nil" })
	util.validate("snippets", snippets, { "table" })
	util.validate("opts", opts, { "table", "nil" })

	opts = opts or {}
	opts.refresh_notify = opts.refresh_notify or true

	-- when ft is nil, snippets already use this format.
	if ft then
		snippets = {
			[ft] = snippets,
		}
	end
	-- update type.
	snippets = snippets --[[@as {[string]: LuaSnip.Snippet[]}]]

	snippet_collection.add_snippets(snippets, {
		type = opts.type or "snippets",
		key = opts.key,
		override_priority = opts.override_priority,
		default_priority = opts.default_priority,
	})

	if opts.refresh_notify then
		for ft_, _ in pairs(snippets) do
			API.refresh_notify(ft_)
		end
	end
end

---@class LuaSnip.Opts.CleanInvalidated
---@field inv_limit? integer If set, invalidated snippets are only cleared if
---  their number exceeds `inv_limit`.

--- Clean invalidated snippets from internal snippet storage.
--- Invalidated snippets are still stored; it might be useful to actually remove
--- them as they still have to be iterated during expansion.
---@param opts? LuaSnip.Opts.CleanInvalidated Additional, optional arguments.
function API.clean_invalidated(opts)
	opts = opts or {}
	snippet_collection.clean_invalidated(opts)
end

---@class LuaSnip.Opts.ActivateNode
---@field strict? boolean Only activate nodes one could usually jump to.
---  (Defaults to false)
---@field select? boolean Whether to select the entire node, or leave the
---  cursor at the position it is currently at. (Defaults to true)
---@field pos? LuaSnip.BytecolBufferPosition Where to look for the node.
---  (Defaults to the position of the cursor)

--- Lookup a node by position and activate (ie. jump into) it.
---@param opts? LuaSnip.Opts.ActivateNode Additional, optional arguments.
function API.activate_node(opts)
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
	cut_keys = function() return require("luasnip.util.select").cut_keys end,
	-- keep select_keys for backwards-compatibility.
	select_keys = function() return require("luasnip.util.select").cut_keys end,
	pre_yank =  function() return require("luasnip.util.select").pre_yank end,
	post_yank = function() return require("luasnip.util.select").post_yank end,
}

-- This will never be executed.
-- It is used to define the type annotation class for all lazy attributes by tricking LuaLS into
-- exploring all targeted functions and use their documentation for the class methods.
if false then
	---@class LuaSnip.LazyAPI
	_ = {
		s = require("luasnip.nodes.snippet").S,
		sn = require("luasnip.nodes.snippet").SN,
		t = require("luasnip.nodes.textNode").T,
		f = require("luasnip.nodes.functionNode").F,
		i = require("luasnip.nodes.insertNode").I,
		c = require("luasnip.nodes.choiceNode").C,
		d = require("luasnip.nodes.dynamicNode").D,
		r = require("luasnip.nodes.restoreNode").R,
		snippet = require("luasnip.nodes.snippet").S,
		snippet_node = require("luasnip.nodes.snippet").SN,
		parent_indexer = require("luasnip.nodes.snippet").P,
		indent_snippet_node = require("luasnip.nodes.snippet").ISN,
		text_node = require("luasnip.nodes.textNode").T,
		function_node = require("luasnip.nodes.functionNode").F,
		insert_node = require("luasnip.nodes.insertNode").I,
		choice_node = require("luasnip.nodes.choiceNode").C,
		dynamic_node = require("luasnip.nodes.dynamicNode").D,
		restore_node = require("luasnip.nodes.restoreNode").R,
		parser = require("luasnip.util.parser"),
		config = require("luasnip.config"),
		multi_snippet = require("luasnip.nodes.multiSnippet").new_multisnippet,
		snippet_source = require("luasnip.session.snippet_collection.source"),
		cut_keys = require("luasnip.util.select").cut_keys,
		-- keep select_keys for backwards-compatibility.
		select_keys = require("luasnip.util.select").cut_keys,
		pre_yank = require("luasnip.util.select").pre_yank,
		post_yank = require("luasnip.util.select").post_yank,
	}
end

API.get_snippet_filetypes = util.get_snippet_filetypes
API.session = session
API.env_namespace = Environ.env_namespace
API.setup = require("luasnip.config").setup
API.extend_decorator = extend_decorator
API.log = require("luasnip.util.log")

---@class LuaSnip: LuaSnip.API, LuaSnip.LazyAPI
ls = lazy_table(API, ls_lazy)
return ls
