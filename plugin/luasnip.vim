inoremap <silent> <Plug>luasnip-expand-or-jump <cmd>lua require'luasnip'.expand_or_jump()<Cr>
inoremap <silent> <Plug>luasnip-expand-snippet <cmd>lua require'luasnip'.expand()<Cr>
inoremap <silent> <Plug>luasnip-next-choice <cmd>lua require'luasnip'.change_choice(1)<Cr>
inoremap <silent> <Plug>luasnip-prev-choice <cmd>lua require'luasnip'.change_choice(-1)<Cr>
inoremap <silent> <Plug>luasnip-jump-next <cmd>lua require'luasnip'.jump(1)<Cr>
inoremap <silent> <Plug>luasnip-jump-prev <cmd>lua require'luasnip'.jump(-1)<Cr>

noremap <silent> <Plug>luasnip-delete-check <cmd>lua require'luasnip'.unlink_current_if_deleted()<Cr>
noremap! <silent> <Plug>luasnip-delete-check <cmd>lua require'luasnip'.unlink_current_if_deleted()<Cr>

noremap <silent> <Plug>luasnip-expand-repeat <cmd>lua require'luasnip'.expand_repeat()<Cr>
noremap! <silent> <Plug>luasnip-expand-repeat <cmd>lua require'luasnip'.expand_repeat()<Cr>

snoremap <silent> <Plug>luasnip-expand-or-jump <cmd>lua require'luasnip'.expand_or_jump()<Cr>
snoremap <silent> <Plug>luasnip-expand-snippet <cmd>lua require'luasnip'.expand()<Cr>
snoremap <silent> <Plug>luasnip-next-choice <cmd>lua require'luasnip'.change_choice(1)<Cr>
snoremap <silent> <Plug>luasnip-prev-choice <cmd>lua require'luasnip'.change_choice(-1)<Cr>
snoremap <silent> <Plug>luasnip-jump-next <cmd>lua require'luasnip'.jump(1)<Cr>
snoremap <silent> <Plug>luasnip-jump-prev <cmd>lua require'luasnip'.jump(-1)<Cr>

command! LuaSnipUnlinkCurrent lua require'luasnip'.unlink_current()
command! LuaSnipListAvailable lua print(vim.inspect(require'luasnip'.available()))

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

lua require('luasnip.config')._setup()

" register these during startup so lazy_load will also load filetypes whose
" events fired only before lazy_load is actually called.
" (BufWinEnter -> lazy_load() wouldn't load any files without these).
augroup _luasnip_lazy_load
	au!
	au BufWinEnter,FileType * lua require('luasnip.loaders.from_lua')._load_lazy_loaded(tonumber(vim.fn.expand("<abuf>")))
	au BufWinEnter,FileType * lua require("luasnip.loaders.from_snipmate")._load_lazy_loaded(tonumber(vim.fn.expand("<abuf>")))
	au BufWinEnter,FileType * lua require('luasnip.loaders.from_vscode')._load_lazy_loaded(tonumber(vim.fn.expand("<abuf>")))
augroup END
