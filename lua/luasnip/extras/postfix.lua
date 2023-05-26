local snip = require("luasnip.nodes.snippet").S
local events = require("luasnip.util.events")
local extend_decorator = require("luasnip.util.extend_decorator")
local node_util = require("luasnip.nodes.util")

local matches = {
	default = [[[%w%.%_%-%"%']+$]],
	line = "^.+$",
}

local function generate_opts(match_pattern, user_callback)
	return {
		callbacks = {
			[-1] = {
				[events.pre_expand] = function(snippet, event_args)
					local pos = event_args.expand_pos
					-- [1]: returns table, gets text end-exclusive.
					local line_to_cursor = vim.api.nvim_buf_get_text(
						0,
						pos[1],
						0,
						pos[1],
						pos[2],
						{}
					)[1]
					local postfix_match = line_to_cursor:match(match_pattern)
						or ""
					-- clear postfix_match-text.
					vim.api.nvim_buf_set_text(
						0,
						pos[1],
						pos[2] - #postfix_match,
						pos[1],
						pos[2],
						{ "" }
					)
					local user_env = {}
					if user_callback then
						user_env = user_callback(snippet, event_args) or {}
					end
					local postfix_env_override = {
						env_override = {
							POSTFIX_MATCH = postfix_match,
						},
					}

					return vim.tbl_deep_extend(
						"keep",
						user_env,
						postfix_env_override
					)
				end,
			},
		},
	}
end

local function wrap_condition(user_condition, match_pattern)
	if not user_condition then
		user_condition = require("luasnip.util.util").yes
	end

	return function(line_to_cursor, matched_trigger, captures)
		return line_to_cursor:sub(1, -1 - #matched_trigger):match(match_pattern)
				~= nil
			and user_condition(line_to_cursor, matched_trigger, captures)
	end
end

local function postfix(context, nodes, opts)
	opts = opts or {}
	local user_callback = vim.tbl_get(opts, "callbacks", -1, events.pre_expand)
	vim.validate({
		context = { context, { "string", "table" } },
		nodes = { nodes, "table" },
		opts = { opts, "table" },
		user_callback = { user_callback, { "nil", "function" } },
	})

	context = node_util.wrap_context(context)
	context.wordTrig = false
	local match_pattern = context.match_pattern or matches.default
	context.condition = wrap_condition(context.condition, match_pattern)

	opts = vim.tbl_deep_extend(
		"force",
		opts,
		generate_opts(match_pattern, user_callback)
	)
	return snip(context, nodes, opts)
end
extend_decorator.register(
	postfix,
	{ arg_indx = 1, extend = node_util.snippet_extend_context },
	{ arg_indx = 3 }
)

return {
	postfix = postfix,
	matches = matches,
}
