require'node'
require'snippet'
require'util'

Active_snippet = nil
Ns_id = vim.api.nvim_create_namespace("luasnip")

function Get_active_snip() return Active_snippet end

local function copy(args) return args[1] end

local snippets = {
	S("fn", {
		T({"function "}),
		I(1),
		T({"("}),
		I(2, {"lel", ""}),
		T({")"}),
		F(copy, {2}),
		T({" {","\t"}),
		I(0),
		T({"", "}"})
	})
}

-- returns snippet-object where its trigger matches the end of the line, nil if no match.
local function match_snippet(line)
	for i = 1, #snippets do
		local snip = snippets[i]
		-- if line ends with trigger
		if string.sub(line, #line - #snip.trigger + 1, #line) == snip.trigger then
			local o = vim.deepcopy(snip)
			for j, n in ipairs(snip.nodes) do
				setmetatable(o.nodes[j], getmetatable(n))
			end
			setmetatable(o, getmetatable(snip))
			return o
		end
	end
	return nil
end

local function jump(dir)
	if Active_snippet ~= nil then
		local exit = Active_snippet:jump(dir)
		if exit then
			Active_snippet = Active_snippet.parent
		end
		return true
	end
	return false
end

-- return true and expand snippet if expandable, return false if not.
local function expand_or_jump()
	local line = Get_current_line_to_cursor()
	local snip = match_snippet(line)
	if snip ~= nil then
		snip:indent(line)

		-- remove snippet-trigger, Cursor at start of future snippet text.
		Remove_n_before_cur(#snip.trigger)

		snip:expand()
		return true
	end
	if jump(1) then
		return true
	end
	return false
end

return {
	expand_or_jump = expand_or_jump,
	jump = jump,
	s = S,
	t = T,
	f = F,
	i = I
}
