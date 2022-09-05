" Syntax highlighting for .snippets files
" Hopefully this should make snippets a bit nicer to write!
syn match snipComment '^#.*'
syn match placeHolder '\${\d\+\(:.\{-}\)\=}' contains=snipCommand
syn match tabStop '\$\d\+'
syn match snipEscape '\\\\\|\\`'
syn match snipCommand '\%(\\\@<!\%(\\\\\)*\)\@<=`.\{-}\%(\\\@<!\%(\\\\\)*\)\@<=`'
syn match snippet '^snippet.*' contains=multiSnipText,snipKeyword
syn match snippet '^autosnippet.*' contains=multiSnipText,snipKeyword
syn match snippet '^extends.*' contains=snipKeyword
syn match snippet '^version.*' contains=snipKeyword
syn match snippet '^priority.*' contains=snipKeyword,priority
syn match priority '\d\+' contained
syn match multiSnipText '\S\+ \zs.*' contained
syn match snipKeyword '^(snippet|extends|version|autosnippet|priority)'me=s+8 contained
" normally we'd want a \s in that group, but that doesn't work => cover common
" cases with \t and " ".
syn match snipError "^[^#vsaep\t ].*$"

hi link snippet       Identifier
hi link snipComment   Comment
hi link multiSnipText String
hi link snipKeyword   Keyword
hi link snipEscape    SpecialChar
hi link placeHolder   Special
hi link tabStop       Special
hi link snipCommand   String
hi link snipError     Error
hi link priority      Number
