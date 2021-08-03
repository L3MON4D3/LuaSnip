```
            __                       ____                          
           /\ \                     /\  _`\           __           
           \ \ \      __  __     __ \ \,\L\_\    ___ /\_\  _____   
            \ \ \  __/\ \/\ \  /'__`\\/_\__ \  /' _ `\/\ \/\ '__`\ 
             \ \ \L\ \ \ \_\ \/\ \L\.\_/\ \L\ \/\ \/\ \ \ \ \ \L\ \
              \ \____/\ \____/\ \__/.\_\ `\____\ \_\ \_\ \_\ \ ,__/
               \/___/  \/___/  \/__/\/_/\/_____/\/_/\/_/\/_/\ \ \/ 
                                                             \ \_\ 
                                                              \/_/ 
```

Luasnip is a snippet-engine written entirely in lua. It has some great
features like inserting text (`luasnip-function-node`) or nodes
(`luasnip-dynamic-node`) based on user input, parsing LSP syntax and switching
nodes (`luasnip-choice-node`).

All code-snippets in this help assume that

```lua
local ls = require"luasnip"
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
```

# SNIPPETS

The most direct way to define snippets is `s`: 
```lua
s({trig="trigger"}, {})
```

(This snippet is useless beyond being a minimal example)

`s` accepts, as the first argument, a table with the following possible
entries:

- `trig`: string, plain text by default. The only entry that must be given.
- `namr`: string, can be used by eg. `nvim-compe` to identify the snippet.
- `dscr`: string, textual description of the snippet, \n-separated or table
          for multiple lines.
- `wordTrig`: boolean, if true, the snippet is only expanded if the word
              (`[%w_]+`) before the cursor matches the trigger entirely.
			  True by default.
- `regTrig`: boolean, whether the trigger should be interpreted as a
             lua pattern. False by default.

`s` can also be a single string, in which case it is used instead of `trig`, all
other values being defaulted:

```lua
s("trigger", {})
```

The second argument to `s` is a table containing all nodes that belong to the
snippet. If the table only has a single node, it can be passed directly
without wrapping it in a table.

The third argument is the condition-function. The snippet will be expanded only
if it returns true (default is a function that just returns true).

The fourth and following args are passed to the condition-function(allows
reusing condition-functions).

Snippets contain some interesting tables, eg. `snippet.env` contains variables
used in the LSP-protocol like `TM_CURRENT_LINE` or `TM_FILENAME` or
`snippet.captures`, where capture-groups of regex-triggers are stored. These
tables are primarily useful in dynamic/functionNodes, where the snippet is
passed to the generating function.

Snippets that should be loaded for all files must be put into the
`ls.snippets.all`-table, those only for a specific filetype `ft` belong in
`ls.snippets.ft`.

# TEXTNODE

The most simple kind of node; just text.
```lua
s("trigger", t("Wow! Text!"))
```
This snippet expands to

```
    Wow! Text!⎵
```
Where ⎵ is the cursor.
Multiline-strings can be defined by passing a table of lines rather than a
string:

```lua
s("trigger", t({"Wow! Text!", "And another line."}))
```


# INSERTNODE

These Nodes can be jumped to and from. The functionality is best demonstrated
with an example:

```lua
s("trigger", {
	t({"", "After expanding, the cursor is here ->"}), i(1),
	t({"After jumping forward once, cursor is here ->"}), i(2),
	t({"", "After jumping once more, the snippet is exited there ->"}), i(0),
})
```

The InsertNodes are jumped over in order from `1 to n`.
0-th node is special as it's always the last one.
So the order of InsertNode jump is as follows:
- After expansion, we will be at InsertNode 1.
- After jumping forward, we will be at InsertNode 2.
- After jumping forward again, we will be at InsertNode 0.

If no 0-th InsertNode is found in a snippet, one is automatically inserted
after all other nodes.

It is possible to have mixed order in jumping nodes:
```lua
s("trigger", {
	t({"After jumping forward once, cursor is here ->"}), i(2),
	t({"", "After expanding, the cursor is here ->"}), i(1),
	t({"", "After jumping once more, the snippet is exited there ->"}), i(0),
})
```
The above snippet will use the same jump flow as above which is: 
- After expansion, we will be at InsertNode 1.
- After jumping forward, we will be at InsertNode 2.
- After jumping forward again, we will be at InsertNode 0.

It's possible to have easy-to-overwrite text inside an InsertNode initially:
```lua
	s("trigger", i(1, "This text is SELECTed after expanding the snippet."))
```
This initial text is defined the same way as textNodes, eg. can be multiline.

0-th Node can not have placeholder text. So the following is not possible
```lua
	s("trigger", i(0, "Not Valid"))
```


# FUNCTIONNODE

Function Nodes insert text based on the content of other nodes using a
user-defined function:
```lua
 s("trig", {
 	i(1),
 	f(function(args, user_arg_1) return args[1][1] .. user_arg_1 end,
 		{1},
 		"Will be appended to text from i(0)"),
 	i(0)
 })
```
The first parameter of `f` is the function. Its parameters are
	1.: a table of text and the surrounding snippet (ie.
	`{{line1}, {line1, line2}, snippet}`). the snippet-indent will be removed
	from all lines following the first.
	The snippet is included here, as it allows access to anything that could be
	useful in functionNodes (ie.  `snippet.env` or `snippet.captures`, which
	contains capture groups of regex-triggered snippets).

	2.: Any parameters passed to `f` behind the second (included to more easily
	reuse functions, ie. ternary if based on text in an insertNode).

The second parameter is a table of indizes of jumpable nodes whose text is
passed to the function. The table may be empty, in this case the function is
evaluated once upon snippet-expansion. If the table only has a single node, it
can be passed directly without wrapping it in a table.

The function shall return a string, which will be inserted as-is, or a table
of strings for multiline snippets, here all lines following the first will be
prepended with the snippets' indentation.

Examples:
	Use captures from the regex-trigger using a functionNode:

```lua
 s({trig = "b(%d)", regTrig = true},
 	f(function(args) return
 		"Captured Text: " .. args[1].captures[1] .. "." end, {})
 )
```


# CHOICENODE

ChoiceNodes allow choosing between multiple nodes.

```lua
 s("trig", c(1, {
 	t("Ugh boring, a text node"),
 	i(nil, "At least I can edit something now..."),
 	f(function(args) return "Still only counts as text!!" end, {})
 }))
```

`c()` expects as it first arg, as with any jumpable node, its position in the
jumplist, and as its second a table with nodes, the choices.

Jumpable nodes that normally expect an index as their first parameter don't
need one inside a choiceNode; their index is the same as the choiceNodes'.



# SNIPPETNODE

SnippetNodes directly insert their contents into the surrounding snippet.
This is useful for choiceNodes, which only accept one child, or dynamicNodes,
where nodes are created at runtime and inserted as a snippetNode.

Syntax is similar to snippets, however, where snippets require a table
specifying when to expand, snippetNodes, similar to insertNodes, expect a
number, as they too are jumpable:
```lua
 s("trig", sn(1, {
 	t("basically just text "),
 	i(1, "And an insertNode.")
 }))
```

Note that snippetNodes don't expect an `i(0)`.



# DYNAMICNODE

Very similar to functionNode: returns a snippetNode instead of just text,
which makes them very powerful.

Parameters:
1. position (just like all jumpable nodes)
2. function: Similar to functionNodes' function, first parameter is the
	`table of text` from nodes the dynamicNode depends on(also without snippet-indent), the second,
	unlike functionNode, is a user-defined table, `old_state`.
	This table can contain anything, its main usage is to preserve
	information from the previous snippetNode:
	If the dynamicNode depends on another node it may be reconstructed,
	which means all user input to the dynamicNode is lost. Using
	`old_state`, the user may pass eg. insertNodes and then get their text
	upon reconstruction to initialize the new nodes with.
	The `old_state` table must be stored inside the snippetNode returned by
	the function.
	All parameters following the second are user defined.
3. Nodes the dynamicNode depends on: if any of these trigger an update,
	the dynamicNodes function will be executed and the result inserted at
	the nodes place. Can be a single node or a table of nodes.
4. The fourth and following parameters are user defined, anything passed
	here will also be passed to the function (arg 2) following its second
	parameter (easy to reuse similar functions with small changes).

```lua
 local function lines(args, old_state, initial_text)
 	local nodes = {}
 	if not old_state then old_state = {} end

 	-- count is nil for invalid input.
 	local count = tonumber(args[1][1])
 	-- Make sure there's a number in args[1].
 	if count then
 		for j=1, count do
 			local iNode
 			if old_state and old_state[j] then
 				-- old_text is used internally to determine whether
 				-- dependents should be updated. It is updated whenever the
 				-- node is left, but remains valid when the node is no
 				-- longer 'rendered', whereas get_text() grabs the text
 				-- directly form the node.
 				iNode = i(j, old_state[j].old_text)
 			else
 			  iNode = i(j, initial_text)
 			end
 			nodes[2*j-1] = iNode

 			-- linebreak
 			nodes[2*j] = t({"",""})
 			-- Store insertNode in old_state, potentially overwriting older
 			-- nodes.
 			old_state[j] = iNode
 		end
 	else
 		nodes[1] = t("Enter a number!")
 	end
 	
 	local snip = sn(nil, nodes)
 	snip.old_state = old_state
 	return snip
 end

 ...

 s("trig", {
 	i(1, "1"),
 	-- pos, function, nodes, user_arg1
 	d(2, lines, {1}, "Sample Text")
 })
```
This snippet would start out as "1\nSample Text" and, upon changing the 1 to
eg. 3, it would change to "3\nSample Text\nSample Text\nSample Text". Text
that was inserted into any of the dynamicNodes insertNodes is kept when
changing to a bigger number.



# VSCODE SNIPPETS LOADER

As luasnip is capable of loading the same format of plugins as vscode, it also
includes an easy way for loading those automatically. You just have to call:
```lua
 	require("luasnip/loaders/from_vscode").load(opts) -- opts can be ommited
```
Where `opts` is a table containing the keys:
	-  `paths`: List of paths to load as a table or as a single string separated
	   by a comma, if not set it's `'runtimepath'`, you can start the paths with
	   `~/` or `./` to indicate that the path is relative to your home or to
	   the folder where your `$MYVIMRC` resides (useful to add your snippets).
	-  `exclude`: List of languages to exclude, by default is empty.
	-  `include`: List of languages to include, by default is not set.

The last two are useful mainly to avoid loading snippets from 3erd parties you don't wanna include.

Keep in mind that it will extend your `snippets` table, so do it after setting
your snippets or you will have to extend the table as well.

Another way of using the loader is making it lazily

```lua
 	require("luasnip/loaders/from_vscode").lazy_load(opts) -- opts can be ommited
```

In this case `opts` only accepts paths (`runtimepath` if any). That will load
the general snippets (the ones of filetype 'all') and those of the filetype
of the buffers, you open every time you open a new one (but it won't reload them).


