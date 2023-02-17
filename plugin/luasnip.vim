function! luasnip#expandable()
	return luaeval('require("luasnip").expandable()')
endfunction

function! luasnip#expand_or_jumpable()
	return luaeval('require("luasnip").expand_or_jumpable()')
endfunction

function! luasnip#expand_or_locally_jumpable()
	return luaeval('require("luasnip").expand_or_locally_jumpable()')
endfunction

function! luasnip#locally_jumpable(direction)
	return luaeval('require("luasnip").locally_jumpable(_A)', a:direction)
endfunction

function! luasnip#jumpable(direction)
	return luaeval('require("luasnip").jumpable(_A)', a:direction)
endfunction

function! luasnip#choice_active()
	return luaeval('require("luasnip").choice_active()')
endfunction
