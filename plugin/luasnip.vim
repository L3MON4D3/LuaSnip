inoremap <silent> <Plug>luasnip-expand-or-jump <cmd>lua require'luasnip'.expand_or_jump()<Cr>
inoremap <silent> <Plug>luasnip-next-choice <cmd>lua require'luasnip'.change_choice(1)<Cr>
inoremap <silent> <Plug>luasnip-jump-next <cmd>lua require'luasnip'.jump(1)<Cr>
inoremap <silent> <Plug>luasnip-jump-prev <cmd>lua require'luasnip'.jump(-1)<Cr>

snoremap <silent> <Plug>luasnip-expand-or-jump <cmd>lua require'luasnip'.expand_or_jump()<Cr>
snoremap <silent> <Plug>luasnip-next-choice <cmd>lua require'luasnip'.change_choice(1)<Cr>
snoremap <silent> <Plug>luasnip-jump-next <cmd>lua require'luasnip'.jump(1)<Cr>
snoremap <silent> <Plug>luasnip-jump-prev <cmd>lua require'luasnip'.jump(-1)<Cr>

command! LuaSnipUnlinkCurrent lua require'luasnip'.unlink_current()


augroup luasnip
	au!
	autocmd InsertLeavePre * lua require('luasnip').active_update_dependents()
augroup END
