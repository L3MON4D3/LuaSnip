if vim.version().major == 0 and vim.version().minor < 9 then
	-- need LanguageTree:tree_for_range and don't want to go through the hassle
	-- of differentiating multiple version of query.get/parse.
	error("treesitter_postfix does not support neovim < 0.9")
end

local snip = require("luasnip.nodes.snippet").S
local ts = require("luasnip.extras._treesitter")
local node_util = require("luasnip.nodes.util")
local extend_decorator = require("luasnip.util.extend_decorator")
local tbl = require("luasnip.util.table")
local util = require("luasnip.util.util")

--- Normalize the arguments passed to treesitter_postfix into a function that
--- returns treesitter-matches to the specified query+captures.
---@param opts LuaSnip.extra.MatchTSNodeOpts
---@return LuaSnip.extra.MatchTSNodeFunc
local function generate_match_tsnode_func(opts)
	local match_opts = {}

	if opts.query then
		match_opts.query =
			vim.treesitter.query.parse(opts.query_lang, opts.query)
	else
		match_opts.query = vim.treesitter.query.get(
			opts.query_lang,
			opts.query_name or "luasnip"
		)
	end

	match_opts.generator = ts.captures_iter(opts.match_captures or "prefix")

	if type(opts.select) == "function" then
		match_opts.selector = opts.select
	elseif type(opts.select) == "string" then
		match_opts.selector = ts.builtin_tsnode_selectors[opts.select]
		assert(
			match_opts.selector,
			"Selector " .. opts.select .. "is not known"
		)
	else
		match_opts.selector = ts.builtin_tsnode_selectors.any
	end

	---@param parser LuaSnip.extra.TSParser
	---@param pos { [1]: number, [2]: number }
	return function(parser, pos)
		return parser:match_at(
			match_opts, --[[@as LuaSnip.extra.MatchTSNodeOpts]]
			pos
		)
	end
end

local function make_reparse_enter_and_leave_func(
	reparse,
	bufnr,
	trigger_region,
	trigger
)
	if reparse == "live" then
		local context = ts.FixBufferContext.new(bufnr, trigger_region, trigger)
		return function()
			return context:enter()
		end, function(_)
			context:leave()
		end
	elseif reparse == "copy" then
		local parser, source =
			ts.reparse_buffer_after_removing_match(bufnr, trigger_region)
		return function()
			return parser, source
		end, function()
			parser:destroy()
		end
	else
		return function()
			return vim.treesitter.get_parser(bufnr), bufnr
		end, function(_) end
	end
end

---Optionally parse the buffer
---@param reparse boolean|string|nil
---@param real_resolver function
---@return fun(snippet, line_to_cursor, matched_trigger, captures):table?
local function wrap_with_reparse_context(reparse, real_resolver)
	return function(snippet, line_to_cursor, matched_trigger, captures)
		local bufnr = vim.api.nvim_win_get_buf(0)
		local cursor = util.get_cursor_0ind()
		local trigger_region = {
			row = cursor[1],
			col_range = {
				-- includes from, excludes to.
				cursor[2] - #matched_trigger,
				cursor[2],
			},
		}

		local enter, leave = make_reparse_enter_and_leave_func(
			reparse,
			bufnr,
			trigger_region,
			matched_trigger
		)
		local parser, source = enter()
		if parser == nil or source == nil then
			return nil
		end

		local ret = real_resolver(
			snippet,
			line_to_cursor,
			matched_trigger,
			captures,
			parser,
			source,
			bufnr,
			{ cursor[1], cursor[2] - #matched_trigger }
		)

		leave()

		return ret
	end
end

---@param match_tsnode LuaSnip.extra.MatchTSNodeFunc Determines the constraints on the matched node.
local function generate_resolve_expand_param(match_tsnode, user_resolver)
	---@param snippet any
	---@param line_to_cursor string
	---@param matched_trigger string
	---@param captures any
	---@param parser LanguageTree
	---@param source number|string
	---@param bufnr number
	---@param pos { [1]: number, [2]: number }
	return function(
		snippet,
		line_to_cursor,
		matched_trigger,
		captures,
		parser,
		source,
		bufnr,
		pos
	)
		local ts_parser = ts.TSParser.new(bufnr, parser, source)
		if ts_parser == nil then
			return
		end

		local row, col = unpack(pos)

		local best_match, prefix_node = match_tsnode(ts_parser, { row, col })

		if best_match == nil or prefix_node == nil then
			return nil
		end

		local start_row, start_col, _, _ = prefix_node:range()

		local env = {
			LS_TSMATCH = vim.split(ts_parser:get_node_text(prefix_node), "\n"),
			-- filled subsequently.
			LS_TSDATA = {},
		}
		for capture_name, node in pairs(best_match) do
			env["LS_TSCAPTURE_" .. capture_name:upper()] =
				vim.split(ts_parser:get_node_text(node), "\n")

			local from_r, from_c, to_r, to_c = node:range()
			env.LS_TSDATA[capture_name] = {
				type = node:type(),
				range = { { from_r, from_c }, { to_r, to_c } },
			}
		end

		local ret = {
			trigger = matched_trigger,
			captures = captures,
			clear_region = {
				from = {
					start_row,
					start_col,
				},
				to = {
					pos[1],
					pos[2] + #matched_trigger,
				},
			},
			env_override = env,
		}

		if user_resolver then
			local user_res = user_resolver(
				snippet,
				line_to_cursor,
				matched_trigger,
				captures
			)
			if user_res then
				ret = vim.tbl_deep_extend(
					"force",
					ret,
					user_res,
					{ env_override = {} }
				)
			else
				return nil
			end
		end

		return ret
	end
end

local function generate_simple_parent_lookup_function(lookup_fun)
	---@param types string|string[]
	---@return LuaSnip.extra.MatchTSNodeFunc
	return function(types)
		local type_checker = tbl.list_to_set(types)
		---@param parser LuaSnip.extra.TSParser
		---@param pos { [1]: number, [2]: number }
		return function(parser, pos)
			-- check node just before the position.
			local root = parser:get_node_at_pos({ pos[1], pos[2] - 1 })

			if root == nil then
				return
			end

			---@param node TSNode
			local check_node_exclude_pos = function(node)
				local _, _, end_row, end_col = node:range(false)
				return end_row == pos[1] and end_col == pos[2]
			end
			---@param node TSNode
			local check_node_type = function(node)
				return type_checker[node:type()]
			end

			local prefix_node = lookup_fun(root, function(node)
				return check_node_type(node) and check_node_exclude_pos(node)
			end)
			if prefix_node == nil then
				return nil, nil
			end
			return {}, prefix_node
		end
	end
end

---@param n number
local function find_nth_parent(n)
	---@param parser LuaSnip.extra.TSParser
	---@param pos { [1]: number, [2]: number }
	return function(parser, pos)
		local inner_node = parser:get_node_at_pos({ pos[1], pos[2] - 1 })

		if inner_node == nil then
			return
		end

		---@param node TSNode
		local check_node_exclude_pos = function(node)
			local _, _, end_row, end_col = node:range(false)
			return end_row == pos[1] and end_col == pos[2]
		end

		return {}, ts.find_nth_parent(inner_node, n, check_node_exclude_pos)
	end
end

local function treesitter_postfix(context, nodes, opts)
	opts = opts or {}
	vim.validate({
		context = { context, { "string", "table" } },
		nodes = { nodes, "table" },
		opts = { opts, "table" },
	})

	context = node_util.wrap_context(context)
	context.wordTrig = false

	---@type LuaSnip.extra.MatchTSNodeFunc
	local match_tsnode_func
	if type(context.matchTSNode) == "function" then
		match_tsnode_func = context.matchTSNode
	else
		match_tsnode_func = generate_match_tsnode_func(context.matchTSNode)
	end

	local expand_params_resolver = generate_resolve_expand_param(
		match_tsnode_func,
		context.resolveExpandParams
	)

	context.resolveExpandParams =
		wrap_with_reparse_context(context.reparseBuffer, expand_params_resolver)

	return snip(context, nodes, opts)
end

extend_decorator.register(
	treesitter_postfix,
	{ arg_indx = 1, extend = node_util.snippet_extend_context },
	{ arg_indx = 3 }
)

return {
	treesitter_postfix = treesitter_postfix,
	builtin = {
		tsnode_matcher = {
			find_topmost_types = generate_simple_parent_lookup_function(
				ts.find_topmost_parent
			),
			find_first_types = generate_simple_parent_lookup_function(
				ts.find_first_parent
			),
			find_nth_parent = find_nth_parent,
		},
	},
}
