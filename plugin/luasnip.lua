vim.filetype.add({
	extension = { snippets = "snippets" },
})

local function silent_map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc or "" })
end

silent_map("i", "<Plug>luasnip-expand-or-jump", function()
	require("luasnip").expand_or_jump()
end, "LuaSnip: Expand or jump in the current snippet")
silent_map("i", "<Plug>luasnip-expand-snippet", function()
	require("luasnip").expand()
end, "LuaSnip: Expand the current snippet")
silent_map("i", "<Plug>luasnip-next-choice", function()
	require("luasnip").change_choice(1)
end, "LuaSnip: Change to the next choice from the choiceNode")
silent_map("i", "<Plug>luasnip-prev-choice", function()
	require("luasnip").change_choice(-1)
end, "LuaSnip: Change to the previous choice from the choiceNode")
silent_map("i", "<Plug>luasnip-jump-next", function()
	require("luasnip").jump(1)
end, "LuaSnip: Jump to the next node")
silent_map("i", "<Plug>luasnip-jump-prev", function()
	require("luasnip").jump(-1)
end, "LuaSnip: Jump to the previous node")

silent_map("n", "<Plug>luasnip-delete-check", function()
	require("luasnip").unlink_current_if_deleted()
end, "LuaSnip: Removes current snippet from jumplist")
silent_map("!", "<Plug>luasnip-delete-check", function()
	require("luasnip").unlink_current_if_deleted()
end, "LuaSnip: Removes current snippet from jumplist")

silent_map("", "<Plug>luasnip-expand-repeat", function()
	require("luasnip").expand_repeat()
end, "LuaSnip: Repeat last node expansion")
silent_map("!", "<Plug>luasnip-expand-repeat", function()
	require("luasnip").expand_repeat()
end, "LuaSnip: Repeat last node expansion")

silent_map("s", "<Plug>luasnip-expand-or-jump", function()
	require("luasnip").expand_or_jump()
end, "LuaSnip: Expand or jump in the current snippet")
silent_map("s", "<Plug>luasnip-expand-snippet", function()
	require("luasnip").expand()
end, "LuaSnip: Expand the current snippet")
silent_map("s", "<Plug>luasnip-next-choice", function()
	require("luasnip").change_choice(1)
end, "LuaSnip: Change to the next choice from the choiceNode")
silent_map("s", "<Plug>luasnip-prev-choice", function()
	require("luasnip").change_choice(-1)
end, "LuaSnip: Change to the previous choice from the choiceNode")
silent_map("s", "<Plug>luasnip-jump-next", function()
	require("luasnip").jump(1)
end, "LuaSnip: Jump to the next node")
silent_map("s", "<Plug>luasnip-jump-prev", function()
	require("luasnip").jump(-1)
end, "LuaSnip: Jump to the previous node")

vim.api.nvim_create_user_command("LuaSnipUnlinkCurrent", function()
	require("luasnip").unlink_current()
end, { force = true })

--stylua: ignore
vim.api.nvim_create_user_command("LuaSnipListAvailable", function()
	(require("luasnip.util.vimversion").ge(0,9,0) and vim.print or vim.pretty_print)(require("luasnip").available())
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
