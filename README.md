# LuaSnip
Snippet Engine for Neovim written in Lua.  
WIP, very limited testing.

# Features
- Placeholders
- Text-Transformations using Lua functions
- Conditional Expansion
- Defining nested Snippets
- Filetype-specific Snippets
- Fast, small, simple

# Requirements
Neovim >= 0.5 (extmarks)

# Setup
- Install using eg. [vim-plug](https://github.com/junegunn/vim-plug)
- Add mappings
  - If there is no jump- or expandable Snippet, insert key:
```vim
imap <silent><expr> <Tab> luasnip#expand_or_jumpable() ? '<Plug>luasnip-expand-or-jump' : '<Tab>'
inoremap <silent> <S-Tab> <cmd>lua ls.jump(-1)<Cr>
```
  - Only try expanding the Snippet/jumping:
```vim
imap <silent><expr> <C-l> <cmd>lua require'luasnip'.expand_or_jump()<Cr>
inoremap <silent> <S-Tab> <cmd>lua require'luasnip'.jump(-1)<Cr>
```
- Add Snippets: Snippets have to be added to the `require'luasnip'.snippets`-table.
`Examples` contains more details, for actual snippets take a look at [my Snippets](https://github.com/L3MON4D3/Dotfiles/blob/master/.config/nvim/lua/snips.lua).

Inspired by [vsnip.vim](https://github.com/hrsh7th/vim-vsnip/)
