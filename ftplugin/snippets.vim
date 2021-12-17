" Vim filetype plugin for SnipMate snippets (.snippets files)

if exists("b:did_ftplugin")
    finish
endif
let b:did_ftplugin = 1

let b:undo_ftplugin = "setl et< sts< cms< fdm< fde<"

" Use hard tabs
setlocal noexpandtab softtabstop=0

setlocal commentstring=#\ %s
setlocal nospell
