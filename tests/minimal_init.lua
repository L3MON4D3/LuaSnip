-- plenary.vim must be installed
vim.cmd [[set runtimepath+=.]]
vim.cmd [[runtime! plugin/plenary.vim]]
vim.cmd [[runtime! plugin/luasnip.vim]]

require('luasnip.config').setup {}
