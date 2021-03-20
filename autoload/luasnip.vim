function! luasnip#expand_or_jumpable()
	return luaeval('require("luasnip").expand_or_jumpable()')
endfunction
