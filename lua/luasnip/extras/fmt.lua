local text_node = require("luasnip.nodes.textNode").T
local wrap_nodes = require("luasnip.util.util").wrap_nodes
local extend_decorator = require("luasnip.util.extend_decorator")
local Str = require("luasnip.util.str")
local rp = require("luasnip.extras").rep

-- https://gist.github.com/tylerneylon/81333721109155b2d244
local function copy3(obj, seen)
	-- Handle non-tables and previously-seen tables.
	if type(obj) ~= "table" then
		return obj
	end
	if seen and seen[obj] then
		return seen[obj]
	end

	-- New table; mark it as seen an copy recursively.
	local s = seen or {}
	local res = {}
	s[obj] = res
	for k, v in next, obj do
		res[copy3(k, s)] = copy3(v, s)
	end
	return setmetatable(res, getmetatable(obj))
end

-- Interpolate elements from `args` into format string with placeholders.
--
-- The placeholder syntax for selecting from `args` is similar to fmtlib and
-- Python's .format(), with some notable differences:
-- * no format options (like `{:.2f}`)
-- * 1-based indexing
-- * numbered/auto-numbered placeholders can be mixed; numbered ones set the
--   current index to new value, so following auto-numbered placeholders start
--   counting from the new value (e.g. `{} {3} {}` is `{1} {3} {4}`)
--
-- Arguments:
--   fmt: string with placeholders
--   args: table with list-like and/or map-like keys
--   opts:
--     delimiters: string, 2 distinct characters (left, right), default "{}"
--     strict: boolean, set to false to allow for unused `args`, default true
--     repeat_duplicates: boolean, repeat nodes which have jump_index instead of copying them, default false
-- Returns: a list of strings and elements of `args` inserted into placeholders
local function interpolate(fmt, args, opts)
	local defaults = {
		delimiters = "{}",
		strict = true,
		repeat_duplicates = false,
	}
	opts = vim.tbl_extend("force", defaults, opts or {})

	-- sanitize delimiters
	assert(
		#opts.delimiters == 2,
		'Currently only single-char delimiters are supported, e.g. delimiters="{}" (left, right)'
	)
	assert(
		opts.delimiters:sub(1, 1) ~= opts.delimiters:sub(2, 2),
		"Delimiters must be two _different_ characters"
	)
	local delimiters = {
		left = opts.delimiters:sub(1, 1),
		right = opts.delimiters:sub(2, 2),
		esc_left = vim.pesc(opts.delimiters:sub(1, 1)),
		esc_right = vim.pesc(opts.delimiters:sub(2, 2)),
	}

	-- manage insertion of text/args
	local elements = {}
	local last_index = 0
	local used_keys = {}

	local add_text = function(text)
		if #text > 0 then
			table.insert(elements, text)
		end
	end
	local add_arg = function(placeholder)
		local num = tonumber(placeholder)
		local key
		if num then -- numbered placeholder
			last_index = num
			key = last_index
		elseif placeholder == "" then -- auto-numbered placeholder
			key = last_index + 1
			last_index = key
		else -- named placeholder
			key = placeholder
		end
		assert(
			args[key],
			string.format(
				"Missing key `%s` in format arguments: `%s`",
				key,
				fmt
			)
		)
		-- if the node was already used, insert a copy of it.
		-- The nodes are modified in-place as part of constructing the snippet,
		-- modifying one node twice will lead to UB.
		if used_keys[key] then
			local jump_index = args[key]:get_jump_index() -- For nodes that don't have a jump index, copy it instead
			if not opts.repeat_duplicates or jump_index == nil then
				table.insert(elements, copy3(args[key]))
			else
				table.insert(elements, rp(jump_index))
			end
		else
			table.insert(elements, args[key])
			used_keys[key] = true
		end
	end

	-- iterate keeping a range from previous match, e.g. (not in_placeholder vs in_placeholder)
	-- "Sample {2} string {3}."   OR  "Sample {2} string {3}."
	--       left^--------^right  OR      left^-^right
	local pattern =
		string.format("[%s%s]", delimiters.esc_left, delimiters.esc_right)
	local in_placeholder = false
	local left = 0

	while true do
		local right = fmt:find(pattern, left + 1)
		-- if not found, add the remaining part of string and finish
		if right == nil then
			assert(
				not in_placeholder,
				string.format('Missing closing delimiter: "%s"', fmt:sub(left))
			)
			add_text(fmt:sub(left + 1))
			break
		end
		-- check if the delimiters are escaped
		local delim = fmt:sub(right, right)
		local next_char = fmt:sub(right + 1, right + 1)
		if not in_placeholder and delim == next_char then
			-- add the previous part of the string with a single delimiter
			add_text(fmt:sub(left + 1, right))
			-- and jump over the second one
			left = right + 1
			-- "continue"
		else -- non-escaped delimiter
			assert(
				delim
					== (in_placeholder and delimiters.right or delimiters.left),
				string.format(
					'Found unescaped %s %s placeholder; format[%d:%d]="%s"',
					delim,
					in_placeholder and "inside" or "outside",
					left,
					right,
					fmt:sub(left, right)
				)
			)
			-- add arg/text depending on current state
			local add = in_placeholder and add_arg or add_text
			add(fmt:sub(left + 1, right - 1))
			-- update state
			left = right
			in_placeholder = delim == delimiters.left
		end
	end

	-- sanity check: all arguments were used
	if opts.strict then
		for key, _ in pairs(args) do
			assert(
				used_keys[key],
				string.format("Unused argument: args[%s]", key)
			)
		end
	end

	return elements
end

-- Use a format string with placeholders to interpolate nodes.
--
-- See `interpolate` documentation for details on the format.
--
-- Arguments:
--   str: format string
--   nodes: snippet node or list of nodes
--   opts: optional table
--     trim_empty: boolean, remove whitespace-only first/last lines, default true
--     dedent: boolean, remove all common indent in `str`, default true
--     ... the rest is passed to `interpolate`
-- Returns: list of snippet nodes
local function format_nodes(str, nodes, opts)
	local defaults = {
		trim_empty = true,
		dedent = true,
	}
	opts = vim.tbl_extend("force", defaults, opts or {})

	-- allow to pass a single node
	nodes = wrap_nodes(nodes)

	-- optimization: avoid splitting multiple times
	local lines = nil

	lines = vim.split(str, "\n", true)
	Str.process_multiline(lines, opts)
	str = table.concat(lines, "\n")

	-- pop format_nodes's opts
	for key, _ in ipairs(defaults) do
		opts[key] = nil
	end

	local parts = interpolate(str, nodes, opts)
	return vim.tbl_map(function(part)
		-- wrap strings in text nodes
		if type(part) == "string" then
			return text_node(vim.split(part, "\n", true))
		else
			return part
		end
	end, parts)
end

extend_decorator.register(format_nodes, { arg_indx = 3 })

return {
	interpolate = interpolate,
	format_nodes = format_nodes,
	-- alias
	fmt = format_nodes,
	fmta = extend_decorator.apply(format_nodes, { delimiters = "<>" }),
}
