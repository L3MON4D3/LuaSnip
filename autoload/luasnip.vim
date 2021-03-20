function! luasnip#expand_or_jumpable()
	return luaeval('require("luasnip").expand_or_jumpable()')
endfunction

function! luasnip#choice_active()
	return luaeval('require("luasnip").choice_active()')
endfunction
