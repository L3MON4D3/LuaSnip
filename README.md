# LuaSnip
https://user-images.githubusercontent.com/41961280/122515860-5179fa00-d00e-11eb-91f7-331893f61fbf.mp4

# Features
- Tabstops
- Text-Transformations using Lua functions
- Conditional Expansion
- Defining nested Snippets
- Filetype-specific Snippets
- Choices
- Dynamic Snippet creation
- Regex-Trigger
- Autotriggered Snippets
- Fast
- Parse [LSP-Style](https://microsoft.github.io/language-server-protocol/specification#snippet_syntax) Snippets (Does not, however, support Regex-Transformations)
- Expand LSP-Snippets with [nvim-compe](https://github.com/hrsh7th/nvim-compe) (or its' successor, [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) (requires [cmp_luasnip](https://github.com/saadparwaiz1/cmp_luasnip)))
- Snippet history (jump back into older snippets)

# Drawbacks
- Snippets that make use of the entire functionality of this plugin have to be defined in Lua.

# Requirements
Neovim >= 0.5 (extmarks)

# Setup
- Install using eg. [vim-plug](https://github.com/junegunn/vim-plug)
- Add maps
  <details>
   <summary>in vimscript</summary>
  
    ```vim
    imap <silent><expr> <Tab> luasnip#expand_or_jumpable() ? '<Plug>luasnip-expand-or-jump' : '<Tab>' 
    inoremap <silent> <S-Tab> <cmd>lua require'luasnip'.jump(-1)<Cr>

    snoremap <silent> <Tab> <cmd>lua require('luasnip').jump(1)<Cr>
    snoremap <silent> <S-Tab> <cmd>lua require('luasnip').jump(-1)<Cr>

    imap <silent><expr> <C-E> luasnip#choice_active() ? '<Plug>luasnip-next-choice' : '<C-E>'
    smap <silent><expr> <C-E> luasnip#choice_active() ? '<Plug>luasnip-next-choice' : '<C-E>'
    ```
  </details>
   <details>
   <summary>or in lua (includes supertab-like functionality with nvim-compe)</summary>
 
    ```lua
    local function prequire(...)
    local status, lib = pcall(require, ...)
    if (status) then return lib end
        return nil
    end

    local luasnip = prequire('luasnip')

    local t = function(str)
        return vim.api.nvim_replace_termcodes(str, true, true, true)
    end

    local check_back_space = function()
        local col = vim.fn.col('.') - 1
        if col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') then
            return true
        else
            return false
        end
    end

    _G.tab_complete = function()
        if vim.fn.pumvisible() == 1 then
            return t "<C-n>"
        elseif luasnip and luasnip.expand_or_jumpable() then
            return t "<Plug>luasnip-expand-or-jump"
        elseif check_back_space() then
            return t "<Tab>"
        else
            return vim.fn['compe#complete']()
        end
    end
    _G.s_tab_complete = function()
        if vim.fn.pumvisible() == 1 then
            return t "<C-p>"
        elseif luasnip and luasnip.jumpable(-1) then
            return t "<Plug>luasnip-jump-prev"
        else
            return t "<S-Tab>"
        end
    end

    vim.api.nvim_set_keymap("i", "<Tab>", "v:lua.tab_complete()", {expr = true})
    vim.api.nvim_set_keymap("s", "<Tab>", "v:lua.tab_complete()", {expr = true})
    vim.api.nvim_set_keymap("i", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
    vim.api.nvim_set_keymap("s", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
    vim.api.nvim_set_keymap("i", "<C-E>", "<Plug>luasnip-next-choice", {})
    vim.api.nvim_set_keymap("s", "<C-E>", "<Plug>luasnip-next-choice", {})
    ```
  </details>
- Add Snippets: Snippets have to be added to the `require'luasnip'.snippets`-table.  
  To test if LuaSnip works correctly and see some of the capabilities lua-native snippets have, `:luafile` `Examples/snippets.lua`. 
- Docs: The previously mentioned `Examples/snippets.lua` contains brief descriptions, check `DOC.md` (or `:help luasnip`) for more in-depth explainations.

# Config
- `history`: If true, Snippets that were exited can still be jumped back into. As Snippets are not removed when their text is deleted, they have to be removed manually via `LuasnipUnlinkCurrent`.
- `updateevents`: Choose which events trigger an update of the active nodes' dependents. Default is just `'InsertLeave'`, `'TextChanged,TextChangedI'` would update on every change.
- `store_selection_keys`: Mapping for populating `TM_SELECTED_TEXT` and related variables (not set by default).
- `enable_autosnippets`: Autosnippets are disabled by default to minimize performance penalty if unused. Set to `true` to enable.

Inspired by [vsnip.vim](https://github.com/hrsh7th/vim-vsnip/)

Talk, ask or suggest on [matrix](https://matrix.to/#/%23luasnip:matrix.org)
