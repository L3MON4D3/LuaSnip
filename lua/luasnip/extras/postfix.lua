local snip = require("luasnip.nodes.snippet").S
local events = require("luasnip.util.events")
local extend_decorator = require("luasnip.util.extend_decorator")
local node_util = require("luasnip.nodes.util")
local util = require("luasnip.util.util")

local matches = {
	default = [[[%w%.%_%-%"%']+$]],
	line = "^.+$",
}

local function wrap_resolve_expand_params(match_pattern, user_resolve)
	return function(snippet, line_to_cursor, match, captures)
		if line_to_cursor:sub(1, -1 - #match):match(match_pattern) == nil then
			return nil
		end

		local pos = util.get_cursor_0ind()
		local line_to_cursor_except_match =
			line_to_cursor:sub(1, #line_to_cursor - #match)
		local postfix_match = line_to_cursor_except_match:match(match_pattern)
			or ""
		local res = {
			clear_region = {
				from = { pos[1], pos[2] - #postfix_match - #match },
				to = pos,
			},
			env_override = {
				POSTFIX_MATCH = postfix_match,
			},
		}

		if user_resolve then
			local user_res =
				user_resolve(snippet, line_to_cursor, match, captures)
			if user_res then
				res = vim.tbl_deep_extend("force", res, user_res, {
					env_override = {},
				})
			else
				return nil
			end
		end
		return res
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
	context.resolveExpandParams =
		wrap_resolve_expand_params(match_pattern, context.resolveExpandParams)

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
