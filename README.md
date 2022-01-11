[![LuaSnip](https://img.shields.io/matrix/luasnip:matrix.org?label=Matrix&logo=matrix)](https://matrix.to/#/%23luasnip:matrix.org)
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
- Snippets that make use of the entire functionality of this plugin have to be defined in Lua (but 95% of snippets can be written in lsp-syntax).

# Requirements
Neovim >= 0.5 (extmarks)

# Setup
## Install 
Ie. With [vim-plug](https://github.com/junegunn/vim-plug)
## Keymaps
  <details>
   <summary>in vimscript</summary>
  
```vim
" press <Tab> to expand or jump in a snippet. These can also be mapped separately
" via <Plug>luasnip-expand-snippet and <Plug>luasnip-jump-next.
imap <silent><expr> <Tab> luasnip#expand_or_jumpable() ? '<Plug>luasnip-expand-or-jump' : '<Tab>' 
" -1 for jumping backwards.
inoremap <silent> <S-Tab> <cmd>lua require'luasnip'.jump(-1)<Cr>

snoremap <silent> <Tab> <cmd>lua require('luasnip').jump(1)<Cr>
snoremap <silent> <S-Tab> <cmd>lua require('luasnip').jump(-1)<Cr>

" For changing choices in choiceNodes (not strictly necessary for a basic setup).
imap <silent><expr> <C-E> luasnip#choice_active() ? '<Plug>luasnip-next-choice' : '<C-E>'
smap <silent><expr> <C-E> luasnip#choice_active() ? '<Plug>luasnip-next-choice' : '<C-E>'
```
  </details>
   <details>
   <summary>or in lua (includes supertab-like functionality with nvim-cmp)</summary>

```lua
local function prequire(...)
local status, lib = pcall(require, ...)
if (status) then return lib end
    return nil
end

local luasnip = prequire('luasnip')
local cmp = prequire("cmp")

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
    if cmp and cmp.visible() then
        cmp.select_next_item()
    elseif luasnip and luasnip.expand_or_jumpable() then
        return t("<Plug>luasnip-expand-or-jump")
    elseif check_back_space() then
        return t "<Tab>"
    else
        cmp.complete()
    end
    return ""
end
_G.s_tab_complete = function()
    if cmp and cmp.visible() then
        cmp.select_prev_item()
    elseif luasnip and luasnip.jumpable(-1) then
        return t("<Plug>luasnip-jump-prev")
    else
        return t "<S-Tab>"
    end
    return ""
end

vim.api.nvim_set_keymap("i", "<Tab>", "v:lua.tab_complete()", {expr = true})
vim.api.nvim_set_keymap("s", "<Tab>", "v:lua.tab_complete()", {expr = true})
vim.api.nvim_set_keymap("i", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
vim.api.nvim_set_keymap("s", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
vim.api.nvim_set_keymap("i", "<C-E>", "<Plug>luasnip-next-choice", {})
vim.api.nvim_set_keymap("s", "<C-E>", "<Plug>luasnip-next-choice", {})
```
  </details>
   <details>
   <summary>or in lua with nvim-compe</summary>
 
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
        return t("<Plug>luasnip-expand-or-jump")
    elseif check_back_space() then
        return t "<Tab>"
    else
        return vim.fn['compe#complete']()
    end
    return ""
end
_G.s_tab_complete = function()
    if vim.fn.pumvisible() == 1 then
        return t "<C-p>"
    elseif luasnip and luasnip.jumpable(-1) then
        return t("<Plug>luasnip-jump-prev")
    else
        return t "<S-Tab>"
    end
    return ""
end

vim.api.nvim_set_keymap("i", "<Tab>", "v:lua.tab_complete()", {expr = true})
vim.api.nvim_set_keymap("s", "<Tab>", "v:lua.tab_complete()", {expr = true})
vim.api.nvim_set_keymap("i", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
vim.api.nvim_set_keymap("s", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
vim.api.nvim_set_keymap("i", "<C-E>", "<Plug>luasnip-next-choice", {})
vim.api.nvim_set_keymap("s", "<C-E>", "<Plug>luasnip-next-choice", {})
```
  </details>

For nvim-cmp, it is also possible to follow the [example recommendation](https://github.com/hrsh7th/nvim-cmp/wiki/Example-mappings#luasnip) from the nvim-cmp wiki.


## Add Snippets

- **Vscode-like**: For using snippets from a plugin (eg. [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets)) install it and add
    ```lua
    require("luasnip.loaders.from_vscode").load()
    ```
	somewhere in your config.  
	For more info on the vscode-loader, check the [examples](https://github.com/L3MON4D3/LuaSnip/blob/b5a72f1fbde545be101fcd10b70bcd51ea4367de/Examples/snippets.lua#L501) or [documentation](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#vscode-snippets-loader).

- **Snipmate-like**: Very similar to Vscode-packages: install the a plugin that provides snippets and call the `load`-function:
    ```lua
    require("luasnip.loaders.from_snipmate").load()
    ```
    The snipmate format is very simple, so adding **custom snippets** only requires a few steps:
    - add a directory beside your `init.vim` (or any other place that is in your `runtimepath`) named `snippets`.
    - inside that directory, create files named `<filetype>.snippet` and add snippets for the given filetype in it (for inspiration, check [honza/vim-snippets](https://github.com/honza/vim-snippets/tree/master/snippets)).  
        ``` snipmate
        # comment
        snippet <trigger> <description>
        <snippet-body>
        snippet if C-style if
        if ($1)
        	$0
        ```
    Again, there are some [examples](https://github.com/L3MON4D3/LuaSnip/blob/b5a72f1fbde545be101fcd10b70bcd51ea4367de/Examples/snippets.lua#L517) and an entry in the [docs](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#snipmate-snippets-loader)
- **Lua**: Add the snippets directly to `require("luasnip").snippets.<filetype>`. An example for this can be found [here](https://github.com/L3MON4D3/LuaSnip/blob/b5a72f1fbde545be101fcd10b70bcd51ea4367de/Examples/snippets.lua#L167).  
This can also be done much better (one snippet-file per filetype+command for editing the current filetype) than in the example, see [this entry in the wiki](https://github.com/L3MON4D3/LuaSnip/wiki/Nice-Configs#split-up-snippets-by-filetype-load-on-demand-and-reload-after-change-first-iteration)
## Docs and Exaples
I highly recommend looking into (or better yet, `:luafile`ing) [`Examples/snippets.lua`](https://github.com/L3MON4D3/LuaSnip/blob/master/Examples/snippets.lua) before writing snippets in lua.  
Check [`DOC.md`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md) (or `:help luasnip`) for in-depth explanations of the different nodes.

# Config
- `history`: If true, Snippets that were exited can still be jumped back into. As Snippets are not removed when their text is deleted, they have to be removed manually via `LuasnipUnlinkCurrent`.
- `updateevents`: Choose which events trigger an update of the active nodes' dependents. Default is just `'InsertLeave'`, `'TextChanged,TextChangedI'` would update on every change.
- `region_check_events`: Events on which to leave the current snippet if the cursor is outside its' 'region'. Disabled by default, `'CursorMoved'`, `'CursorHold'` or `'InsertEnter'` seem reasonable.
- `delete_check_events`: When to check if the current snippet was deleted, and if so, remove it from the history. Off by default, `'TextChanged'` (perhaps `'InsertLeave'`, to react to changes done in Insert mode) should work just fine (alternatively, this can also be mapped using `<Plug>luasnip-delete-check`). 
- `store_selection_keys`: Mapping for populating `TM_SELECTED_TEXT` and related variables (not set by default).
- `enable_autosnippets`: Autosnippets are disabled by default to minimize performance penalty if unused. Set to `true` to enable.
- `ext_opts`: Additional options passed to extmarks. Can be used to add passive/active highlight on a per-node-basis (more info in DOC.md)
- `parser_nested_assembler`: Override the default behaviour of inserting a `choiceNode` containing the nested snippet and an empty `insertNode` for nested placeholders (`"${1: ${2: this is nested}}"`). For an example (behaviour more similar to vscode), check [here](https://github.com/L3MON4D3/LuaSnip/wiki/Nice-Configs#imitate-vscodes-behaviour-for-nested-placeholders)
- `ft_func`: Source of possible filetypes for snippets. Defaults to a function, which returns `vim.split(vim.bo.filetype, ".", true)`, but check [filetype_functions](lua/luasnip/extras/filetype_functions.lua) for other options

Inspired by [vsnip.vim](https://github.com/hrsh7th/vim-vsnip/)
