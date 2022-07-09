local ls = require("luasnip")
local cp = require("luasnip.util.functions").copy
local p = require("luasnip.extras._parser_combinator")
local dedent = require("luasnip.util.str").dedent
local M = {}

local T = { EOL = "EOL", TXT = "TXT", INP = "INP" }

local chunk = p.any(
	p.map(p.literal("$$"), function()
		return { T.TXT, "$" }
	end),
	p.map(p.literal("\n"), function()
		return { T.EOL }
	end),
	p.map(p.seq(p.literal("$"), p.pattern("%w*")), function(c)
		return { T.INP, c[1] }
	end),
	p.map(p.pattern("[^\n$]*"), function(c)
		return { T.TXT, c }
	end)
)

M._snippet_chunks = p.star(chunk)

function M._txt_to_snip(txt)
	local t = ls.t
	local s = ls.s
	local i = ls.i
	local f = ls.f
	txt = dedent(txt)

	-- The parser does not handle empty strings
	if txt == "" then
		return s("", t({ "" }))
	end

	local _, chunks, _ = M._snippet_chunks(txt, 1)

	local current_text_arg = { "" }
	local nodes = {}
	local know_inputs = {}
	local last_input_pos = 0

	for _, part in ipairs(chunks) do
		if part[1] == T.TXT then
			current_text_arg[#current_text_arg] = current_text_arg[#current_text_arg]
				.. part[2]
		elseif #current_text_arg > 1 or current_text_arg[1] ~= "" then
			table.insert(nodes, t(current_text_arg))
			current_text_arg = { "" }
		end

		if part[1] == T.EOL then
			table.insert(current_text_arg, "")
		elseif part[1] == T.INP then
			local inp_pos = know_inputs[part[2]]
			if inp_pos then
				table.insert(nodes, f(cp, { inp_pos }))
			else
				last_input_pos = last_input_pos + 1
				know_inputs[part[2]] = last_input_pos
				table.insert(nodes, i(last_input_pos, part[2]))
			end
		end
	end
	if #current_text_arg > 1 or current_text_arg[1] ~= "" then
		table.insert(nodes, t(current_text_arg))
	end
	return s("", nodes)
end

local last_snip = nil
local last_reg = nil

-- Create snippets On The Fly
-- It's advaisable not to use the default register as luasnip will probably
-- override it
function M.on_the_fly(regname)
	regname = regname or ""
	local reg = table.concat(vim.fn.getreg(regname, 1, true), "\n") -- Avoid eol in the last line
	if last_reg ~= reg then
		last_reg = reg
		last_snip = M._txt_to_snip(reg)
	end
	ls.snip_expand(last_snip)
end

return M
