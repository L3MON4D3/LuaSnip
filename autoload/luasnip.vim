function! luasnip#expand_or_jumpable()
	return luaeval('require("luasnip").expand_or_jumpable()')
endfunction

function! luasnip#choice_active()
	return luaeval('require("luasnip").choice_active()')
endfunction

augroup luasnip
	au!
	autocmd InsertLeavePre * lua ls.active_update_dependents()
augroup END
