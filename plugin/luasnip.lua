vim.filetype.add({
	extension = { snippets = "snippets" },
})

local function silent_map(mode, lhs, rhs)
	vim.keymap.set(mode, lhs, rhs, { silent = true })
end

silent_map("i", "<Plug>luasnip-expand-or-jump", function()
	require("luasnip").expand_or_jump()
end)
silent_map("i", "<Plug>luasnip-expand-snippet", function()
	require("luasnip").expand()
end)
silent_map("i", "<Plug>luasnip-next-choice", function()
	require("luasnip").change_choice(1)
end)
silent_map("i", "<Plug>luasnip-prev-choice", function()
	require("luasnip").change_choice(-1)
end)
silent_map("i", "<Plug>luasnip-jump-next", function()
	require("luasnip").jump(1)
end)
silent_map("i", "<Plug>luasnip-jump-prev", function()
	require("luasnip").jump(-1)
end)

silent_map("n", "<Plug>luasnip-delete-check", function()
	require("luasnip").unlink_current_if_deleted()
end)
silent_map("!", "<Plug>luasnip-delete-check", function()
	require("luasnip").unlink_current_if_deleted()
end)

silent_map("", "<Plug>luasnip-expand-repeat", function()
	require("luasnip").expand_repeat()
end)
silent_map("!", "<Plug>luasnip-expand-repeat", function()
	require("luasnip").expand_repeat()
end)

silent_map("s", "<Plug>luasnip-expand-or-jump", function()
	require("luasnip").expand_or_jump()
end)
silent_map("s", "<Plug>luasnip-expand-snippet", function()
	require("luasnip").expand()
end)
silent_map("s", "<Plug>luasnip-next-choice", function()
	require("luasnip").change_choice(1)
end)
silent_map("s", "<Plug>luasnip-prev-choice", function()
	require("luasnip").change_choice(-1)
end)
silent_map("s", "<Plug>luasnip-jump-next", function()
	require("luasnip").jump(1)
end)
silent_map("s", "<Plug>luasnip-jump-prev", function()
	require("luasnip").jump(-1)
end)

vim.api.nvim_create_user_command("LuaSnipUnlinkCurrent", function()
	require("luasnip").unlink_current()
end, { force = true })

--stylua: ignore
vim.api.nvim_create_user_command("LuaSnipListAvailable", function()
	(
		(
			vim.version
			and type(vim.version) == "table"
			and (
				((vim.version().major == 0) and (vim.version().minor >= 9))
				or (vim.version().major > 0) )
		) and vim.print
		  or vim.pretty_print
	)(require("luasnip").available())
end, { force = true })

require("luasnip.config")._setup()

-- register these during startup so lazy_load will also load filetypes whose
-- events fired only before lazy_load is actually called.
-- (BufWinEnter -> lazy_load() wouldn't load any files without these).
vim.api.nvim_create_augroup("_luasnip_lazy_load", {})
vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType" }, {
	callback = function(event)
		require("luasnip.loaders").load_lazy_loaded(tonumber(event.buf))
	end,
	group = "_luasnip_lazy_load",
})
