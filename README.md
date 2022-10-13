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
- Easy Postfix Snippets
- Fast
- Parse [LSP-Style](https://microsoft.github.io/language-server-protocol/specification#snippet_syntax) Snippets either directly in lua, as a vscode package or a snipmate snippet collection.
- Expand LSP-Snippets with [nvim-compe](https://github.com/hrsh7th/nvim-compe) (or its' successor, [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) (requires [cmp_luasnip](https://github.com/saadparwaiz1/cmp_luasnip)))
- Snippet history (jump back into older snippets)
- Resolve filetype at the cursor using Treesitter

# Drawbacks
- Snippets that make use of the entire functionality of this plugin have to be defined in Lua (but 95% of snippets can be written in lsp-syntax).

# Requirements
Neovim >= 0.5 (extmarks)
`jsregexp` for lsp-snippet-transformations (see [here](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#transformations) for some tips on installing it)

# Setup
## Install 
* With your preferred plugin manager i.e. [vim-plug](https://github.com/junegunn/vim-plug) or [packer](https://github.com/wbthomason/packer.nvim)
* LuaSnip uses [Semantic Versioning](https://semver.org) (with some leeway, big patches might end up as a Minor version)!  
  Releases will be tagged as `vMajor.Minor.Patch`, we recommend following the latest Major release.  

  Packer:
  ```lua
  use({"L3MON4D3/LuaSnip", tag = "v<CurrentMajor>.*"})
  ```
  vim-plug:
  ```vim
  Plug 'L3MON4D3/LuaSnip', {'tag': 'v<CurrentMajor>.*'}
  ```
  Consider watching the repos releases so you're notified when a new version becomes available.

## Keymaps
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
`nvim-cmp`'s wiki also contains [an example](https://github.com/hrsh7th/nvim-cmp/wiki/Example-mappings#luasnip) for
setting up a super-tab-like mapping.

## Add Snippets

Check out [the doc](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#loaders) for a general explanation of the
loaders and their benefits. The following list serves only as a short overview.

- **Vscode-like**: To use existing vs-code style snippets from a plugin (eg. [rafamadriz/friendly-snippets](https://github.com/rafamadriz/friendly-snippets)) simply install the plugin and then add
    ```lua
    require("luasnip.loaders.from_vscode").lazy_load()
    ```
	somewhere in your nvim-config. LuaSnip will then load the snippets contained in the plugin on startup.
  You can also easily **load your own custom vscode style snippets** by passing the path to the custom snippet-directory to the load function:
    ```lua
    -- load snippets from path/of/your/nvim/config/my-cool-snippets
    require("luasnip.loaders.from_vscode").lazy_load({ paths = { "./my-cool-snippets" } })
    ```
	For more info on the vscode-loader, check the [examples](https://github.com/L3MON4D3/LuaSnip/blob/b5a72f1fbde545be101fcd10b70bcd51ea4367de/Examples/snippets.lua#L501) or [documentation](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#loaders).

- **Snipmate-like**: Very similar to Vscode-packages: install a plugin that provides snippets and call the `load`-function:
    ```lua
    require("luasnip.loaders.from_snipmate").lazy_load()
    ```
    The snipmate format is very simple, so adding **custom snippets** only requires a few steps:
    - add a directory beside your `init.vim` (or any other place that is in your `runtimepath`) named `snippets`.
    - inside that directory, create files named `<filetype>.snippets` and add snippets for the given filetype in it (for inspiration, check [honza/vim-snippets](https://github.com/honza/vim-snippets/tree/master/snippets)).  
        ``` snipmate
        # comment
        snippet <trigger> <description>
        <snippet-body>
        snippet if C-style if
        if ($1)
        	$0
        ```
    Again, there are some [examples](https://github.com/L3MON4D3/LuaSnip/blob/b5a72f1fbde545be101fcd10b70bcd51ea4367de/Examples/snippets.lua#L517) and [documentation](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#snipmate).  
- **Lua**: Add the snippets by calling `require("luasnip").add_snippets(filetype, snippets)`. An example for this can be found [here](https://github.com/L3MON4D3/LuaSnip/blob/master/Examples/snippets.lua#L190).  
This can also be done much cleaner, with all the benefits that come with using a loader, by using the [loader for lua](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#lua)

There's also a repository collecting snippets for various languages, [molleweide/LuaSnip-snippets.nvim](https://github.com/molleweide/LuaSnip-snippets.nvim)

## Documentation

### Getting started

You have two main choices: use SnipMate/VS Code snippets (easier) or write snippets in Lua (more complex but also more feature-rich).
Here are some suggestions for getting started in either case:

* **SnipMate or VS Code snippets**: if you only want to write/load SnipMate or VS Code snippets and ignore Lua snippets (and this is definitely recommended if you don't yet need Lua snippets' more complicated features), check out the sections on loading [VS Code](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#vscode) or [SnipMate](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#snipmate) packages in `DOC.md`.
  Of those two, SnipMate is definitely the more comfortable way of writing snippets.
* **Lua snippets**: we suggest first watching or reading one of the introductory guides in the [Resources for new users](#resources-for-new-users) section below.
  After getting familiar with the basics, you should check out the important LuaSnip features in the following list:
  * [`config`](https://github.com/L3MON4D3/LuaSnip#config): Notable: `region_check_events` for jumping to the end of snippets the cursor is no longer inside of,
    `delete_check_events` for cleaning up snippets whose text was deleted,
    and `enable_autosnippets` to enable automatic snippet expansion.
  * [`extras`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#extras): This module contains many functions that make writing snippets
    significantly easier;
    `fmt` and `lambda` are especially useful.
  * [`lua-loader`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#lua):
    A very useful way to load snippets, more comfortable than calling `add_snippets`.  
    Also supports hot reload (limited to buffers in the same NeoVim instance as the edited file) and [jumping to the files that provide snippets to the
    current buffer](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#edit_snippets).
  * Advanced nodes:
    [`functionNode`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#functionnode),
    [`dynamicNode`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#functionnode),
    [`choiceNode`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#choicenode) and [`restoreNode`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#restorenode).  
    Instead of reading about them in the doc, the first three are explained very
    well in [this video](https://www.youtube.com/watch?v=KtQZRAkgLqo) by TJ
    DeVries.

### Official docs and examples

Note: instead of immediately reading the official documentation, you may want to check out the [Resources for new users](#resources-for-new-users) section below, since the docs are written more as a reference manual than as a tutorial for new users.

- [`DOC.md`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md) is the main documentation—it gives an overview of how to write snippets; explains the role and use case of each LuaSnip node; shows how to load snippets from Lua, VS Code, and SnipMate formats; and covers the available LuaSnip API.
- `:help luasnip.txt` is a plain text version of `DOC.md` available with Neovim's `:help` feature.
- The file [`Examples/snippets.lua`](https://github.com/L3MON4D3/LuaSnip/blob/master/Examples/snippets.lua) contains many example snippets written in Lua—we highly recommend looking through (or better yet, `:luafile`ing) these example snippets before using LuaSnip's advanced features.
- The [Wiki](https://github.com/L3MON4D3/LuaSnip/wiki) contains some useful LuaSnip extensions and some examples of advanced snippets and configs.
- Configuration is documentated [at the bottom of this README](#config).

【中文版】DOC in Chinese is [here](https://zjp-cn.github.io/neovim0.6-blogs/nvim/luasnip/doc1.html). 

### Resources for new users
Here are some LuaSnip videos and tutorials on the Web:
- [Introductory](https://www.youtube.com/watch?v=Dn800rlPIho) and [advanced](https://www.youtube.com/watch?v=KtQZRAkgLqo) YouTube videos by the one and only [TJ DeVries](https://github.com/tjdevries). Unfortunately there were some breaking changes in LuaSnip since these videos were recorded:
  * Snippets are now added via [`ls.add_snippets`](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#adding-snippets) instead of with `ls.snippets = {}`
- A [guide to writing snippets in Lua](https://www.ejmastnak.com/tutorials/vim-latex/luasnip.html) with LaTeX-themed GIFs and real-life examples by [@ejmastnak](https://github.com/ejmastnak)
- A guide to [moving from UltiSnips to LuaSnip](https://github.com/evesdropper/dotfiles/tree/main/nvim/luasnip#readme) by [@evesdropper](https://github.com/evesdropper), also in a LaTeX context
- An introductory LuaSnip [video tutorial for beginners](https://www.youtube.com/watch?v=ub0REXjhpmk) by Ziontee113

# Config
- `history`: If true, Snippets that were exited can still be jumped back into. As Snippets are not removed when their text is deleted, they have to be removed manually via `LuasnipUnlinkCurrent` if `delete_check_events` is not enabled (set to eg. `'TextChanged'`).
- `update_events`: Choose which events trigger an update of the active nodes' dependents. Default is just `'InsertLeave'`, `'TextChanged,TextChangedI'` would update on every change.
- `region_check_events`: Events on which to leave the current snippet if the cursor is outside its' 'region'. Disabled by default, `'CursorMoved'`, `'CursorHold'` or `'InsertEnter'` seem reasonable.
- `delete_check_events`: When to check if the current snippet was deleted, and if so, remove it from the history. Off by default, `'TextChanged'` (perhaps `'InsertLeave'`, to react to changes done in Insert mode) should work just fine (alternatively, this can also be mapped using `<Plug>luasnip-delete-check`). 
- `store_selection_keys`: Mapping for populating `TM_SELECTED_TEXT` and related variables (not set by default).
- `enable_autosnippets`: Autosnippets are disabled by default to minimize performance penalty if unused. Set to `true` to enable.
- `ext_opts`: Additional options passed to extmarks. Can be used to add passive/active highlight on a per-node-basis (more info in DOC.md)
- `parser_nested_assembler`: Override the default behaviour of inserting a `choiceNode` containing the nested snippet and an empty `insertNode` for nested placeholders (`"${1: ${2: this is nested}}"`). For an example (behaviour more similar to vscode), check [here](https://github.com/L3MON4D3/LuaSnip/wiki/Nice-Configs#imitate-vscodes-behaviour-for-nested-placeholders)
- `ft_func`: Source of possible filetypes for snippets. Defaults to a function, which returns `vim.split(vim.bo.filetype, ".", true)`, but check [filetype_functions](lua/luasnip/extras/filetype_functions.lua) or [the docs](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#filetype_functions) for more options.
- `load_ft_func`: Function to determine which filetypes belong to a given buffer (used for `lazy_loading`). `fn(bufnr)
  -> filetypes (string[])`. Again, there are some examples in [filetype_functions](lua/luasnip/extras/filetype_functions.lua).
- `snip_env`: The global environment will be extended with this table in some places, eg. in files loaded by the [lua-loader](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md#lua-snippets-loader).  
Setting `snip_env` to `{ some_global = "a value" }` will add the global variable `some_global` while evaluating these files.
If you mind the (probably) large number of generated warnings, consider adding the keys set here to the globals
recognized by lua-language-server or add `---@diagnostic disable: undefined-global` somewhere in the affected files.

Inspired by [vsnip.vim](https://github.com/hrsh7th/vim-vsnip/)
