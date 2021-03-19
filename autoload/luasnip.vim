function! luasnip#expand_or_jump()
	return luaeval('require("luasnip").expand_or_jump()')
endfunction

function! luasnip#expand_or_jumpable()
	return luaeval('require("luasnip").expand_or_jumpable()')
endfunction
