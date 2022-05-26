-- Some string processing utility functions
local M = {}

function M.dedent(s)
	local lst = vim.split(s, "\n")
	if #lst > 0 then
		local ind_size = math.huge
		for i, _ in ipairs(lst) do
			local i1, i2 = lst[i]:find("^%s*[^%s]")
			if i1 and i2 < ind_size then
				ind_size = i2
			end
		end
		for i, _ in ipairs(lst) do
			lst[i] = lst[i]:sub(ind_size, -1)
		end
	end
	return table.concat(lst, "\n")
end

function M.aupatescape(s)
	if vim.fn.has("win32") or vim.fn.has("win64") then
		-- windows: replace \ with / for au-pattern.
		s, _ = s:gsub("\\", "/")
	end
	local escaped, _ = s:gsub(",", "\\,")
	return vim.fn.fnameescape(escaped)
end

return M
