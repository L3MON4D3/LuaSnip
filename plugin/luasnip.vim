inoremap <silent> <Plug>luasnip-expand-or-jump <cmd>lua require'luasnip'.expand_or_jump()<Cr>
inoremap <silent> <Plug>luasnip-next-choice <cmd>lua require'luasnip'.change_choice(1)<Cr>
inoremap <silent> <Plug>luasnip-jump-next <cmd>lua require'luasnip'.jump(1)<Cr>
inoremap <silent> <Plug>luasnip-jump-prev <cmd>lua require'luasnip'.jump(-1)<Cr>

snoremap <silent> <Plug>luasnip-expand-or-jump <cmd>lua require'luasnip'.expand_or_jump()<Cr>
snoremap <silent> <Plug>luasnip-next-choice <cmd>lua require'luasnip'.change_choice(1)<Cr>
snoremap <silent> <Plug>luasnip-jump-next <cmd>lua require'luasnip'.jump(1)<Cr>
snoremap <silent> <Plug>luasnip-jump-prev <cmd>lua require'luasnip'.jump(-1)<Cr>

command! LuaSnipUnlinkCurrent lua require'luasnip'.unlink_current()
command! LuaSnipListAvailable lua print(vim.inspect(require'luasnip'.available()))

function! luasnip#expand_or_jumpable()
	return luaeval('require("luasnip").expand_or_jumpable()')
endfunction

function! luasnip#jumpable(direction)
	return luaeval('require("luasnip").jumpable(_A)', a:direction)
endfunction

function! luasnip#choice_active()
	return luaeval('require("luasnip").choice_active()')
endfunction

augroup luasnip
	au!
	execute('autocmd '.luaeval('require"luasnip".config.config.updateevents').' * lua require("luasnip").active_update_dependents()')
augroup END
