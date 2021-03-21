# LuaSnip
Snippet Engine for Neovim written in Lua.  
WIP, very limited testing.  
![Basic-Example](./Examples/basic.gif)
![Choice-Example](./Examples/choices.gif)

# Features
- Placeholders
- Text-Transformations using Lua functions
- Conditional Expansion
- Defining nested Snippets
- Filetype-specific Snippets
- Choices
- Fast, small, simple

# Drawbacks
- Snippets have to defined in Lua, as of now there is no parser.

# Requirements
Neovim >= 0.5 (extmarks)

# Setup
- Install using eg. [vim-plug](https://github.com/junegunn/vim-plug)
- Add mappings  
  - Insert key if jumping/expanding/switching choices is not possible:
  ```vim
  imap <silent><expr> <Tab> luasnip#expand_or_jumpable() ? '<Plug>luasnip-expand-or-jump' : '<Tab>'
  imap <silent><expr> <C-E> luasnip#choice_active() ? '<Plug>luasnip-next-choice' : '<C-E>'
  ```
  - Only try expanding the Snippet/jumping:
  ```vim
  imap <silent><expr> <C-l> <cmd>lua require'luasnip'.expand_or_jump()<Cr>
  inoremap <silent> <S-Tab> <cmd>lua require'luasnip'.jump(-1)<Cr>
  ```
  - Mappings for Jumping in Select:
  ```vim
  snoremap <silent> <Tab> <cmd>lua ls.jump(1)<Cr>
  snoremap <silent> <S-Tab> <cmd>lua ls.jump(-1)<Cr>
  ```
- Add Snippets: Snippets have to be added to the `require'luasnip'.snippets`-table.
`Examples` contains more details, for actual snippets take a look at [my Snippets](https://github.com/L3MON4D3/Dotfiles/blob/master/.config/nvim/lua/snips.lua).

Inspired by [vsnip.vim](https://github.com/hrsh7th/vim-vsnip/)
