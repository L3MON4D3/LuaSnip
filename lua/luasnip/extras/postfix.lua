local snip = require("luasnip.nodes.snippet").S
local events = require("luasnip.util.events")
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

local function postfix(context, nodes, opts)
	opts = opts or {}
	local user_callback = vim.tbl_get(opts, "callbacks", -1, events.pre_expand)
	vim.validate({
		context = { context, { "string", "table" } },
		nodes = { nodes, "table" },
		opts = { opts, "table" },
		user_callback = { user_callback, { "nil", "function" } },
	})

	local match_pattern
	if type(context) == "string" then
		context = {
			trig = context,
		}
		match_pattern = matches.default
	else
		match_pattern = context.match_pattern or matches.default
	end

	context = vim.tbl_deep_extend("keep", context, { wordTrig = false })
	opts = vim.tbl_deep_extend(
		"force",
		opts,
		generate_opts(match_pattern, user_callback)
	)
	return snip(context, nodes, opts)
end

return {
	postfix = postfix,
	matches = matches,
}
