" Vim filetype plugin for SnipMate snippets (.snippets files)

if exists("b:did_ftplugin")
    finish
endif
let b:did_ftplugin = 1

let b:undo_ftplugin = "setl cms< fdm< fde<"

setlocal foldmethod=expr foldexpr=getline(v:lnum)=~'^#\\\|^e\\\|^p'?0:getline(v:lnum)!~'^\\t\\\|^\ \\\|^$'?'>1':1

setlocal commentstring=#\ %s
setlocal nospell
