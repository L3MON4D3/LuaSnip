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
For basic setup like mappings and installing, check the README.

All code-snippets in this help assume that

```lua
local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local isn = ls.indent_snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local events = require("luasnip.util.events")
local ai = require("luasnip.nodes.absolute_indexer")
local extras = require("luasnip.extras")
local l = extras.lambda
local rep = extras.rep
local p = extras.partial
local m = extras.match
local n = extras.nonempty
local dl = extras.dynamic_lambda
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local conds = require("luasnip.extras.expand_conditions")
local postfix = require("luasnip.extras.postfix").postfix
local types = require("luasnip.util.types")
local parse = require("luasnip.util.parser").parse_snippet
```

As noted in [the Lua section](#lua):

> By default, the names from [`luasnip.config.snip_env`][snip-env-src] will be used, but it's possible to customize them by setting `snip_env` in `setup`. 

Furthermore, note that while this document assumes you have defined `ls` to be `require("luasnip")`, it is **not** provided in the default set of variables.

<!-- panvimdoc-ignore-start -->

Note: the source code of snippets in GIFs is actually
[here](https://github.com/zjp-CN/neovim0.6-blogs/commit/2bff84ef53f8da5db9dcf2c3d97edb11b2bf68cd),
and it's slightly different with the code below.

<!-- panvimdoc-ignore-end -->

# BASICS
In LuaSnip, snippets are made up of `nodes`. These can contain either

- static text (`textNode`)
- text that can be edited (`insertNode`)
- text that can be generated from the contents of other nodes (`functionNode`)
- other nodes
    - `choiceNode`: allows choosing between two nodes (which might contain more
    nodes)
    - `restoreNode`: store and restore input to nodes
- or nodes that can be generated based on input (`dynamicNode`).

Snippets are always created using the `s(trigger:string, nodes:table)`-function.
It is explained in more detail in [SNIPPETS](#snippets), but the gist is that
it creates a snippet that contains the nodes specified in `nodes`, which will be
inserted into a buffer if the text before the cursor matches `trigger` when
`ls.expand` is called.  

## Jump-index
Nodes that can be jumped to (`insertNode`, `choiceNode`, `dynamicNode`,
`restoreNode`, `snippetNode`) all require a "jump-index" so luasnip knows the
order in which these nodes are supposed to be visited ("jumped to").  

```lua
s("trig", {
	i(1), t"text", i(2), t"text again", i(3)
})
```

These indices don't "run" through the entire snippet, like they do in
textmate-snippets (`"$1 ${2: $3 $4}"`), they restart at 1 in each nested
snippetNode:
```lua
s("trig", {
	i(1), t" ", sn(2, {
		t" ", i(1), t" ", i(2)
	})
})
```
(roughly equivalent to the given textmate-snippet).

## Adding Snippets
The snippets for a given filetype have to be added to luasnip via
`ls.add_snippets(filetype, snippets)`. Snippets that should be accessible
globally (in all filetypes) have to be added to the special filetype `all`.
```lua
ls.add_snippets("all", {
	s("ternary", {
		-- equivalent to "${1:cond} ? ${2:then} : ${3:else}"
		i(1, "cond"), t(" ? "), i(2, "then"), t(" : "), i(3, "else")
	})
})
```
It is possible to make snippets from one filetype available to another using
`ls.filetype_extend`, more info on that [here](#api-reference).

# NODE

Every node accepts, as its last parameter, an optional table of arguments.
There are some common ones (e.g. [`node_ext_opts`](#ext_opts)), and some that
only apply to some nodes (`user_args` for both function and dynamicNode).
These `opts` are only mentioned if they accept options that are not common to
all nodes.

## Node-Api:

- `get_jump_index()`: this method returns the jump-index of a node. If a node 
  doesn't have a jump-index, this method returns `nil` instead.

# SNIPPETS

The most direct way to define snippets is `s`:
```lua
s({trig="trigger"}, {})
```
(This snippet is useless beyond serving as a minimal example)

`s(context, nodes, opts) -> snippet`

- `context`: Either table or a string. Passing a string is equivalent to passing

  ```lua
  {
  	trig = context
  }
  ```

  The following keys are valid:
  - `trig`: string, plain text by default. The only entry that must be given.
  - `name`: string, can be used by e.g. `nvim-compe` to identify the snippet.
  - `dscr`: string, description of the snippet, \n-separated or table
    for multiple lines.
  - `wordTrig`: boolean, if true, the snippet is only expanded if the word
    (`[%w_]+`) before the cursor matches the trigger entirely.
    True by default.
  - `regTrig`: boolean, whether the trigger should be interpreted as a
    lua pattern. False by default.
  - `docstring`: string, textual representation of the snippet, specified like
    `dscr`. Overrides docstrings loaded from json.
  - `docTrig`: string, for snippets triggered using a lua pattern: define the
    trigger that is used during docstring-generation.
  - `hidden`: boolean, hint for completion-engines.
    If set, the snippet should not show up when querying snippets.
  - `priority`: positive number, Priority of the snippet, 1000 by default.  
	Snippets with high priority will be matched to a trigger before those with a
	lower one.
    The priority for multiple snippets can also be set in `add_snippets`.
  - `snippetType`: string, should be either `snippet` or `autosnippet` (ATTENTION:
    singular form is used), decides whether this snippet has to be triggered by
    `ls.expand()` or whether is triggered automatically (don't forget to set
    `ls.config.setup({ enable_autosnippets = true })` if you want to use this
    feature). If unset it depends on how the snippet is added of which type the
    snippet will be.

- `nodes`: A single node, or a list of nodes. The nodes that make up the
  snippet.

- `opts`: A table, with the following valid keys:

  - `condition`: `fn(line_to_cursor, matched_trigger, captures) -> bool`, where
      - `line_to_cursor`: `string`, the line up to the cursor.
      - `matched_trigger`: `string`, the fully matched trigger (can be retrieved
      	from `line_to_cursor`, but we already have that info here :D)
      - `captures`: if the trigger is pattern, this list contains the
      	capture-groups. Again, could be computed from `line_to_cursor`, but we
      	already did so.

	The snippet will be expanded only if this function returns true (default is
	a function that just returns `true`).  
    The function is called before the text on the line is modified in any way.
  - `show_condition`: `f(line_to_cursor) -> bool`.  
    - `line_to_cursor`: `string`, the line up to the cursor.  

	This function is (should be) evaluated by completion-engines, indicating
	whether the snippet should be included in current completion candidates.  
    Defaults to a function returning `true`.  
    This is different from `condition` because `condition` is evaluated by
    LuaSnip on snippet expansion (and thus has access to the matched trigger and
	captures), while `show_condition` is (should be) evaluated by the
	completion-engine when scanning for available snippet candidates.
  - `callbacks`: Contains functions that are called upon entering/leaving a node
    of this snippet.  
	For example: to print text upon entering the _second_ node of a snippet,
	`callbacks` should be set as follows:
    ```lua
    {
    	-- position of the node, not the jump-index!!
    	-- s("trig", {t"first node", t"second node", i(1, "third node")}).
    	[2] = {
    		[events.enter] = function(node, _event_args) print("2!") end
    	}
    }
    ```
    To register a callback for the snippets' own events, the key `[-1]` may
    be used.
    More info on events [here](#events)
  - `child_ext_opts`, `merge_child_ext_opts`: Control `ext_opts` applied to the
  	children of this snippet. More info on those [here](#ext_opts).

The `opts`-table can also be passed to e.g. `snippetNode` and
`indentSnippetNode`, but only `callbacks` and the `ext_opts`-related options are
used there.

### Snippet-Data

Snippets contain some interesting tables during runtime:

- `snippet.env`: Contains variables used in the LSP-protocol, for example
  `TM_CURRENT_LINE` or `TM_FILENAME`. It's possible to add customized variables
  here too, check [Environment Namespaces](#environment-namespaces)
- `snippet.captures`: If the snippet was triggered by a pattern (`regTrig`), and
  the pattern contained capture-groups, they can be retrieved here.
- `snippet.trigger`: The string that triggered this snippet. Again, only
  interesting if the snippet was triggered through `regTrig`, for getting the
  full match.

These variables/tables primarily come in handy in `dynamic/functionNodes`, where
the snippet can be accessed through the immediate parent (`parent.snippet`),
which is passed to the function.
(in most cases `parent == parent.snippet`, but the `parent` of the dynamicNode
is not always the surrounding snippet, it could be a `snippetNode`).

## Snippet-Api:

- `invalidate()`: call this method to effectively remove the snippet. The
  snippet will no longer be able to expand via `expand` or `expand_auto`. It
  will also be hidden from lists (at least if the plugin creating the list
  respects the `hidden`-key), but it might be necessary to call
  `ls.refresh_notify(ft)` after invalidating snippets.


# TEXTNODE

The most simple kind of node; just text.
```lua
s("trigger", { t("Wow! Text!") })
```
This snippet expands to

```
    Wow! Text!⎵
```
Where ⎵ is the cursor.
Multiline-strings can be defined by passing a table of lines rather than a
string:

```lua
s("trigger", {
	t({"Wow! Text!", "And another line."})
})
```

`t(text, node_opts)`:

- `text`: `string` or `string[]`
- `node_opts`: `table`, see [here](#node)

# INSERTNODE

These Nodes contain editable text and can be jumped to- and from (e.g.
traditional placeholders and tabstops, like `$1` in textmate-snippets).

The functionality is best demonstrated with an example:

```lua
s("trigger", {
	t({"After expanding, the cursor is here ->"}), i(1),
	t({"", "After jumping forward once, cursor is here ->"}), i(2),
	t({"", "After jumping once more, the snippet is exited there ->"}), i(0),
})
```

<!-- panvimdoc-ignore-start -->

![InsertNode](https://user-images.githubusercontent.com/25300418/184359293-7248c2af-81b4-4754-8a85-7a2459f69cfc.gif)

<!-- panvimdoc-ignore-end -->

The InsertNodes are visited in order `1,2,3,..,n,0`.  
(The jump-index 0 also _has_ to belong to an `insertNode`!)
So the order of InsertNode-jumps is as follows:

1. After expansion, the cursor is at InsertNode 1,
2. after jumping forward once at InsertNode 2,
3. and after jumping forward again at InsertNode 0.

If no 0-th InsertNode is found in a snippet, one is automatically inserted
after all other nodes.

The jump-order doesn't have to follow the "textual" order of the nodes:
```lua
s("trigger", {
	t({"After jumping forward once, cursor is here ->"}), i(2),
	t({"", "After expanding, the cursor is here ->"}), i(1),
	t({"", "After jumping once more, the snippet is exited there ->"}), i(0),
})
```
The above snippet will behave as follows:

1. After expansion, we will be at InsertNode 1.
2. After jumping forward, we will be at InsertNode 2.
3. After jumping forward again, we will be at InsertNode 0.

An **important** (because here luasnip differs from other snippet-engines) detail
is that the jump-indices restart at 1 in nested snippets:
```lua
s("trigger", {
	i(1, "First jump"),
	t(" :: "),
	sn(2, {
		i(1, "Second jump"),
		t" : ",
		i(2, "Third jump")
	})
})
```

<!-- panvimdoc-ignore-start -->

![InsertNode2](https://user-images.githubusercontent.com/25300418/184359299-c813b3d2-5445-47c9-af88-d9106e78fa77.gif)

<!-- panvimdoc-ignore-end -->

as opposed to e.g. the textmate-syntax, where tabstops are snippet-global:
```snippet
${1:First jump} :: ${2: ${3:Third jump} : ${4:Fourth jump}}
```
(this is not exactly the same snippet of course, but as close as possible)
(the restart-rule only applies when defining snippets in lua, the above
textmate-snippet will expand correctly when parsed).

`i(jump_index, text, node_opts)`

- [`jump_index`](#jump-index): `number`, this determines when this node will be jumped to.
- `text`: `string|string[]`, a single string for just one line, a list with >1
  entries for multiple lines.
  This text will be SELECTed when the `insertNode` is jumped into.
- `node_opts`: `table`, see [here](#node)

If the `jump_index` is `0`, replacing its' `text` will leave it outside the
`insertNode` (for reasons, check out Luasnip#110).


# FUNCTIONNODE

Function Nodes insert text based on the content of other nodes using a
user-defined function:

```lua
local function fn(
  args,     -- text from i(2) in this example i.e. { { "456" } }
  parent,   -- parent snippet or parent node
  user_args -- user_args from opts.user_args 
)
   return '[' .. args[1][1] .. user_args .. ']'
end

s("trig", {
  i(1), t '<-i(1) ',
  f(fn,  -- callback (args, parent, user_args) -> string
    {2}, -- node indice(s) whose text is passed to fn, i.e. i(2)
    { user_args = { "user_args_value" }} -- opts
  ),
  t ' i(2)->', i(2), t '<-i(2) i(0)->', i(0)
})
```

<!-- panvimdoc-ignore-start -->

![f_node_example](https://user-images.githubusercontent.com/3051781/185458218-5aad8099-c808-4772-95ed-febac0b5c5ff.gif)

<!-- panvimdoc-ignore-end -->

`f(fn, argnode_references, node_opts)`:
- `fn`: `function(argnode_text, parent, user_args1,...,user_argsn) -> text`  
  - `argnode_text`: `string[][]`, the text currently contained in the argnodes
    (e.g. `{{line1}, {line1, line2}}`). The snippet-indent will be removed from
    all lines following the first.

  - `parent`: The immediate parent of the `functionNode`.  
    It is included here as it allows easy access to some information that could
    be useful in functionNodes (see [here](#snippet-data) for some examples).  
    Many snippets access the surrounding snippet just as `parent`, but if the
    `functionNode` is nested within a `snippetNode`, the immediate parent is a
    `snippetNode`, not the surrounding snippet (only the surrounding snippet
    contains data like `env` or `captures`).

  - `user_args`: The `user_args` passed in `opts`. Note that there may be multiple user_args
    (e.g. `user_args1, ..., user_argsn`).
  
  `fn` shall return a string, which will be inserted as-is, or a table of
  strings for multiline-string, here all lines following the first will be
  prefixed with the snippets' indentation.

- `argnode_references`: `node_reference[]|node_refernce|nil`.  
  Either no, a single, or multiple [node-references](#node_reference).
  Changing any of these will trigger a re-evaluation of `fn`, and insertion of
  the updated text.  
  If no node-reference is passed, the `functionNode` is evaluated once upon
  expansion.

- `node_opts`: `table`, see [here](#node). One additional key is supported:
  - `user_args`: `any[]`, these will be passed to `fn` as `user_arg1`-`user_argn`.
    These make it easier to reuse similar functions, for example a functionNode
    that wraps some text in different delimiters (`()`, `[]`, ...).

    ```lua
    local function reused_func(_,_, user_arg1)
        return user_arg1
    end

    s("trig", {
        f(reused_func, {}, {
            user_args = {"text"}
        }),
        f(reused_func, {}, {
            user_args = {"different text"}
        }),
    })
    ```

    <!-- panvimdoc-ignore-start -->
    
    ![FunctionNode2](https://user-images.githubusercontent.com/25300418/184359244-ef83b8f7-28a3-45ff-a2af-5b564f213749.gif)
    
    <!-- panvimdoc-ignore-end -->

**Examples**:

- Use captures from the regex-trigger using a functionNode:

  ```lua
  s({trig = "b(%d)", regTrig = true},
  	f(function(args, snip) return
  		"Captured Text: " .. snip.captures[1] .. "." end, {})
  )
  ```
  
  <!-- panvimdoc-ignore-start -->
  
  ![FunctionNode3](https://user-images.githubusercontent.com/25300418/184359248-6b13a80c-f644-4979-a566-958c65a4e047.gif)
  
  <!-- panvimdoc-ignore-end -->

- `argnodes_text` during function-evaluation:

  ```lua
  s("trig", {
  	i(1, "text_of_first"),
  	i(2, {"first_line_of_second", "second_line_of_second"}),
  	f(function(args, snip)
  		--here
  	-- order is 2,1, not 1,2!!
  	end, {2, 1} )})
  ```
  
  <!-- panvimdoc-ignore-start -->
  
  ![FunctionNode4](https://user-images.githubusercontent.com/25300418/184359259-ebb7cfc0-e30b-4735-9627-9ead45d9f27c.gif)
  
  <!-- panvimdoc-ignore-end -->
  
  At `--here`, `args` would look as follows (provided no text was changed after
  expansion):
  ```lua
  args = {
  	{"first_line_of_second", "second_line_of_second"},
  	{"text_of_first"}
  }
  ```
  
  <!-- panvimdoc-ignore-start -->
  
  ![FunctionNode5](https://user-images.githubusercontent.com/25300418/184359263-89323682-6128-40ea-890e-b184a1accf80.gif)
  
  <!-- panvimdoc-ignore-end -->

- [`absolute_indexer`](#absolute_indexer):

  ```lua
  s("trig", {
  	i(1, "text_of_first"),
  	i(2, {"first_line_of_second", "second_line_of_second"}),
  	f(function(args, snip)
  		-- just concat first lines of both.
  		return args[1][1] .. args[2][1]
  	end, {ai[2], ai[1]} )})
  ```
  
  <!-- panvimdoc-ignore-start -->
  
  ![FunctionNode6](https://user-images.githubusercontent.com/25300418/184359271-018a703d-a9c8-4c9d-8833-b16495be5b08.gif)
  
  <!-- panvimdoc-ignore-end -->

If the function only performs simple operations on text, consider using
the `lambda` from [`luasnip.extras`](#extras)

## NODE_REFERENCE
Node-references are used to refer to other nodes in various parts of luasnip's
API.  
For example, argnodes in functionNode, dynamicNode or lambda are
node-references.  
These references can be either of:
  - `number`: the jump-index of the node.
  This will be resolved relative to the parent of the node this is passed to.
  (So, only nodes with the same parent can be referenced. This is very easy to
  grasp, but also limiting)
  - [`absolute_indexer`](#absolute_indexer): the absolute position of the
  node. This will come in handy if the referred-to node is not in the same
  snippet/snippetNode as the one this node-reference is passed to.
  - `node`: just the node. Usage of this is discouraged, since it can lead to
  subtle errors (for example if the node passed here is captured in a closure
  and therefore not copied with the remaining tables in the snippet (there's a
  big comment about just this in commit 8bfbd61)).

# CHOICENODE

ChoiceNodes allow choosing between multiple nodes.

```lua
 s("trig", c(1, {
 	t("Ugh boring, a text node"),
 	i(nil, "At least I can edit something now..."),
 	f(function(args) return "Still only counts as text!!" end, {})
 }))
```

<!-- panvimdoc-ignore-start -->

![ChoiceNode](https://user-images.githubusercontent.com/25300418/184359378-09d83ec0-2580-4a0e-8f75-61bd168903ba.gif)

<!-- panvimdoc-ignore-end -->

`c(jump_index, choices, node_opts)`

- [`jump_index`](#jump-index): `number`, since choiceNodes can be jumped to, they need their
  jump-indx.
- `choices`: `node[]|node`, the choices. The first will be initialliy active.
  A list of nodes will be turned into a `snippetNode`.
- `node_opts`: `table`. `choiceNode` supports the keys common to all nodes
  described [here](#node), and one additional key:
  - `restore_cursor`: `false` by default. If it is set, and the node that was
    being edited also appears in the switched-to choice (can be the case if a
    `restoreNode` is present in both choice) the cursor is restored relative to
    that node.  
    The default is `false` as enabling might lead to decreased performance. It's
    possible to override the default by wrapping the `choiceNode`-constructor
    in another function that sets `opts.restore_cursor` to `true` and then using
    that to construct `choiceNode`s:
      ```lua
      local function restore_cursor_choice(pos, choices, opts)
          if opts then
              opts.restore_cursor = true
          else
              opts = {restore_cursor = true}
          end
          return c(pos, choices, opts)
      end
      ```

Jumpable nodes that normally expect an index as their first parameter don't
need one inside a choiceNode; their jump-index is the same as the choiceNodes'.

As it is only possible (for now) to change choices from within the choiceNode,
make sure that all of the choices have some place for the cursor to stop at!  
This means that in `sn(nil, {...nodes...})` `nodes` has to contain e.g. an
`i(1)`, otherwise luasnip will just "jump through" the nodes, making it
impossible to change the choice.

```lua
c(1, {
	t"some text", -- textNodes are just stopped at.
	i(nil, "some text"), -- likewise.
	sn(nil, {t"some text"}) -- this will not work!
	sn(nil, {i(1), t"some text"}) -- this will.
})
```

The active choice for a choiceNode can be changed by either calling one of
`ls.change_choice(1)` (forwards) or `ls.change_choice(-1)` (backwards), or by
calling `ls.set_choice(choice_indx)`.  
One way to easily interact with choiceNodes is binding `change_choice(1/-1)` to
keys:

```lua
-- set keybinds for both INSERT and VISUAL.
vim.api.nvim_set_keymap("i", "<C-n>", "<Plug>luasnip-next-choice", {})
vim.api.nvim_set_keymap("s", "<C-n>", "<Plug>luasnip-next-choice", {})
vim.api.nvim_set_keymap("i", "<C-p>", "<Plug>luasnip-prev-choice", {})
vim.api.nvim_set_keymap("s", "<C-p>", "<Plug>luasnip-prev-choice", {})
```

Apart from this, there is also a [picker](#select_choice) where no cycling is necessary and any
choice can be selected right away, via `vim.ui.select`.

# SNIPPETNODE

SnippetNodes directly insert their contents into the surrounding snippet.
This is useful for `choiceNode`s, which only accept one child, or
`dynamicNode`s, where nodes are created at runtime and inserted as a
`snippetNode`.

Their syntax is similar to `s`, however, where snippets require a table
specifying when to expand, `snippetNode`s, similar to `insertNode`s, expect
a jump-index.

```lua
 s("trig", sn(1, {
 	t("basically just text "),
 	i(1, "And an insertNode.")
 }))
```

<!-- panvimdoc-ignore-start -->

![SnippetNode](https://user-images.githubusercontent.com/25300418/184359349-2127147e-2f57-4612-bdb5-4c9eafc93fad.gif)

<!-- panvimdoc-ignore-end -->

`sn(jump_index, nodes, node_opts)`

- [`jump_index`](#jump-index): `number`, the usual.
- `nodes`: `node[]|node`, just like for `s`.  
  Note that `snippetNode`s don't accept an `i(0)`, so the jump-indices of the nodes
  inside them have to be in `1,2,...,n`.
- `node_opts`: `table`: again, all [common](#node) keys are supported, but also
  - `callbacks`,
  - `child_ext_opts` and
  - `merge_child_ext_opts`,

  which are further explained in [`SNIPPETS`](#snippets).

# INDENTSNIPPETNODE

By default, all nodes are indented at least as deep as the trigger. With these
nodes it's possible to override that behaviour:

```lua
s("isn", {
	isn(1, {
		t({"This is indented as deep as the trigger",
		"and this is at the beginning of the next line"})
	}, "")
})
```

<!-- panvimdoc-ignore-start -->

![IndentSnippetNode](https://user-images.githubusercontent.com/25300418/184359281-acc62f04-f130-48b6-9ad8-c0775726507a.gif)

<!-- panvimdoc-ignore-end -->

(Note the empty string passed to isn).

Indent is only applied after linebreaks, so it's not possible to remove indent
on the line where the snippet was triggered using `ISN` (That is possible via
regex-triggers where the entire line before the trigger is matched).

Another nice usecase for `ISN` is inserting text, e.g. `//` or some other comment-
string before the nodes of the snippet:

```lua
s("isn2", {
	isn(1, t({"//This is", "A multiline", "comment"}), "$PARENT_INDENT//")
})
```

<!-- panvimdoc-ignore-start -->

![IndentSnippetNode2](https://user-images.githubusercontent.com/25300418/184359286-e29ba70e-4ccc-472a-accb-af849ca1a68d.gif)

<!-- panvimdoc-ignore-end -->

Here the `//` before `This is` is important, once again, because indent is only
applied after linebreaks.
To enable such usage, `$PARENT_INDENT` in the indentstring is replaced by the
parent's indent (duh).

`isn(jump_index, nodes, indentstring, node_opts)`

All of these except `indentstring` are exactly the same as [`snippetNode`](#snippetnode).

- `indentstring`: `string`, will be used to indent the nodes inside this
  `snippetNode`.  
  All occurences of `"$PARENT_INDENT"` are replaced with the actual indent of
  the parent.

# DYNAMICNODE

Very similar to functionNode, but returns a snippetNode instead of just text,
which makes them very powerful as parts of the snippet can be changed based on
user-input.

`d(jump_index, function, node-references, opts)`:

- [`jump_index`](#jump-index): `number`, just like all jumpable nodes, its' position in the
   jump-list.
- `function`: `fn(args, parent, old_state, user_args) -> snippetNode`
   This function is called when the argnodes' text changes. It should generate
   and returns (wrapped inside a `snippetNode`) nodes, these will be inserted at
   the dynamicNodes place.  
   `args`, `parent` and `user_args` are also explained in
   [FUNCTIONNODE](#functionnode)
   - `args`: `table of text` (`{{"node1line1", "node1line2"}, {"node2line1"}}`)
     from nodes the `dynamicNode` depends on.
   - `parent`: the immediate parent of the `dynamicNode`.
   - `old_state`: a user-defined table. This table may contain anything, its
   	 intended usage is to preserve information from the previously generated
   	 `snippetNode`: If the `dynamicNode` depends on other nodes it may be
   	 reconstructed, which means all user input (text inserted in `insertNodes`,
   	 changed choices) to the previous dynamicNode is lost.  
     The `old_state` table must be stored in `snippetNode` returned by
     the function (`snippetNode.old_state`).  
     The second example below illustrates the usage of `old_state`.
   - `user_args`: passed through from `dynamicNode`-opts, may be more than one
   	 argument.
- `node_references`: `node_reference[]|node_references|nil`,
  [References](#node_reference) to the nodes the dynamicNode depends on: if any
  of these trigger an update (for example if the text inside them
  changes), the `dynamicNode`s' function will be executed, and the result
  inserted at the `dynamicNodes` place.  
  (`dynamicNode` behaves exactly the same as `functionNode` in this regard).

- `opts`: In addition to the [usual](#node) keys, there is, again, 
  - `user_args`, which is described in [FUNCTIONNODE](#functionnode).

**Examples**:

This `dynamicNode` inserts an `insertNode` which copies the text inside the
first `insertNode`.
```lua
s("trig", {
	t"text: ", i(1), t{"", "copy: "},
	d(2, function(args)
			-- the returned snippetNode doesn't need a position; it's inserted
			-- "inside" the dynamicNode.
			return sn(nil, {
				-- jump-indices are local to each snippetNode, so restart at 1.
				i(1, args[1])
			})
		end,
	{1})
})
```

<!-- panvimdoc-ignore-start -->

![DynamicNode](https://user-images.githubusercontent.com/25300418/184359404-c1081b6c-99e5-4eb1-85c7-7f2e875d7296.gif)

<!-- panvimdoc-ignore-end -->

This snippet makes use of `old_state` to count the number of updates.  
To store/restore values generated by the `dynamicNode` or entered into
`insert/choiceNode`, consider using the shortly-introduced `restoreNode` instead
of `old_state`.

```lua
local function count(_, _, old_state)
	old_state = old_state or {
		updates = 0
	}

	old_state.updates = old_state.updates + 1

	local snip = sn(nil, {
		t(tostring(old_state.updates))
	})

	snip.old_state = old_state
	return snip
end

...

ls.add_snippets("all",
	s("trig", {
		i(1, "change to update"),
		d(2, count, {1})
	})
)
```

<!-- panvimdoc-ignore-start -->

![DynamicNode2](https://user-images.githubusercontent.com/25300418/184359408-8d6df582-2a9e-4e6c-8937-5424bf7f6ecb.gif)

<!-- panvimdoc-ignore-end -->

As with `functionNode`, `user_args` can be used to reuse similar `dynamicNode`-
functions.

# RESTORENODE

This node can store and restore a snippetNode as-is. This includes changed
choices and changed text. Its' usage is best demonstrated by an example:

```lua
s("paren_change", {
	c(1, {
		sn(nil, { t("("), r(1, "user_text"), t(")") }),
		sn(nil, { t("["), r(1, "user_text"), t("]") }),
		sn(nil, { t("{"), r(1, "user_text"), t("}") }),
	}),
}, {
	stored = {
		-- key passed to restoreNodes.
		["user_text"] = i(1, "default_text")
	}
})
```

<!-- panvimdoc-ignore-start -->

![RestoreNode](https://user-images.githubusercontent.com/25300418/184359328-3715912a-8a32-43b6-91b7-6b012c9c3ccd.gif)

<!-- panvimdoc-ignore-end -->

Here the text entered into `user_text` is preserved upon changing choice.

`r(jump_index, key, nodes, node_opts)`:

- [`jump_index`](#jump-index), when to jump to this node.
- `key`, `string`: `restoreNode`s with the same key share their content.
- `nodes`, `node[]|node`: the content of the `restoreNode`.  
  Can either be a single node, or a table of nodes (both of which will be
  wrapped inside a `snippetNode`, except if the single node already is a
  `snippetNode`).  
  The content for a given key may be defined multiple times, but if the
  contents differ, it's undefined which will actually be used.  
  If a key's content is defined in a `dynamicNode`, it will not be initially
  used for `restoreNodes` outside that `dynamicNode`. A way around this
  limitation is defining the content in the `restoreNode` outside the
  `dynamicNode`.

The content for a key may also be defined in the `opts`-parameter of the
snippet-constructor, as seen in the example above. The `stored`-table accepts
the same values as the `nodes`-parameter passed to `r`.
If no content is defined for a key, it defaults to the empty `insertNode`.

An important-to-know limitation of `restoreNode` is that, for a given key, only
one may be visible at a time. See
[this issue](https://github.com/L3MON4D3/LuaSnip/issues/234) for details.

The `restoreNode` is especially useful for storing input across updates of a
`dynamicNode`. Consider this:

```lua
local function simple_restore(args, _)
	return sn(nil, {i(1, args[1]), i(2, "user_text")})
end

s("rest", {
	i(1, "preset"), t{"",""},
	d(2, simple_restore, 1)
}),
```

<!-- panvimdoc-ignore-start -->

![RestoreNode2](https://user-images.githubusercontent.com/25300418/184359337-0962dd5e-a18b-4df1-8c74-3d04a17998ab.gif)

<!-- panvimdoc-ignore-end -->

Every time the `i(1)` in the outer snippet is changed, the text inside the
`dynamicNode` is reset to `"user_text"`. This can be prevented by using a
`restoreNode`:

```lua
local function simple_restore(args, _)
	return sn(nil, {i(1, args[1]), r(2, "dyn", i(nil, "user_text"))})
end

s("rest", {
	i(1, "preset"), t{"",""},
	d(2, simple_restore, 1)
}),
```
Now the entered text is stored.

`RestoreNode`s indent is not influenced by `indentSnippetNodes` right now. If
that really bothers you feel free to open an issue.

<!-- panvimdoc-ignore-start -->

![RestoreNode3](https://user-images.githubusercontent.com/25300418/184359340-35c24160-10b0-4f72-849e-1015f59ed599.gif)

<!-- panvimdoc-ignore-end -->

# ABSOLUTE_INDEXER

A more capable way of [referencing nodes](#node_reference)!  
Using only [`jump indices`](#jump-index), accessing an outer `i(1)` isn't possible
from inside e.g. a snippetNode, since only nodes with the same parent can be
referenced (jump indices are interpreted relative to the parent of the node
that's passed the reference).  
The `absolute_indexer` can be used to reference nodes based on their absolute
position in the snippet, which lifts this restriction.  

```lua
s("trig", {
	i(1), c(2, {
		sn(nil, {
			t"cannot access the argnode :(", f(function(args) return args[1] end, {???})
		}),
		t"sample_text"
	})
})
```

Using `absolute_indexer`, it's possible to do so:
```lua
s("trig", {
	i(1), c(2, {
		sn(nil, { i(1),
			t"can access the argnode :)", f(function(args) return args[1] end, ai[1])
		}),
		t"sample_text"
	})
})
```

<!-- panvimdoc-ignore-start -->

![AbsoluteIndexer](https://user-images.githubusercontent.com/25300418/184359369-3bbd2b30-33d1-4a5d-9474-19367867feff.gif)

<!-- panvimdoc-ignore-end -->

There are some quirks in addressing nodes:
```lua
s("trig", {
	i(2), -- ai[2]: indices based on jump-index, not position.
	sn(1, { -- ai[1]
		i(1), -- ai[1][1]
		t"lel", -- not addressable.
		i(2) -- ai[1][2]
	}),
	c(3, { -- ai[3]
		i(nil), -- ai[3][1]
		t"lel", -- ai[3][2]: choices are always addressable.
	}),
	d(4, function() -- ai[4]
		return sn(nil, { -- ai[4][0]
			i(1), -- ai[4][0][1]
		})
	end, {})
	}))
	r(5, "restore_key", -- ai[5]
		i(1) -- ai[5][0][1]: restoreNodes always store snippetNodes.
	)
	r(6, "restore_key_2", -- ai[6]
		sn(nil, { -- ai[6][0]
			i(1) -- ai[6][0][1]
		})
	)
	}))
})
```

Note specifically that the index of a dynamicNode differs from that of the
generated snippetNode, and that restoreNodes (internally) always store a
snippetNode, so even if the restoreNode only contains one node, that node has
to be accessed as `ai[restoreNodeIndx][0][1]`.

`absolute_indexer`s' can be constructed in different ways:
```lua
ai[1][2][3] == ai(1, 2, 3) == ai{1, 2, 3}
```

# EXTRAS

## Lambda
A shortcut for `functionNode`s that only do very basic string-
manipulation.  
`l(lambda, argnodes)`:

- `lambda`: An object created by applying string-operations to `l._n`, objects
  representing the `n`th argnode.  
  For example: 
  - `l._1:gsub("a", "e")` replaces all occurences of "a" in the text of the
  first argnode with "e", or
  - `l._1 .. l._2` concats text of the first and second argnode.
  If an argnode contains multiple lines of text, they are concatenated with
  `"\n"` prior to any operation.  
- `argnodes`, [`node-references`](#node_reference), just like in function- and
  dynamicNode.

There are many examples for `lambda` in `Examples/snippets.lua`

## Match
`match` can insert text based on a predicate (again, a shorthand for `functionNode`).

`match(argnodes, condition, then, else)`, where

* `argnode`: A single [`node-reference`](#node_reference). May not be nil, or
	a table.
* `condition` may be either of
  * `string`: interpreted as a lua-pattern. Matched on the `\n`-joined (in case
    it's multiline) text of the first argnode (`args[1]:match(condition)`).
  * `function`: `fn(args, snip) -> bool`: takes the same parameters as the
    `functionNode`-function, any value other than nil or false is interpreted
    as a match.
  * `lambda`: `l._n` is the `\n`-joined text of the nth argnode.  
    Useful if string-manipulations have to be performed before the string is matched.  
    Should end with `match`, but any other truthy result will be interpreted
    as matching.

* `then` is inserted if the condition matches,
* `else` if it does not.  

Both `then` and `else` can be either text, lambda or function (with the same parameters as
specified above).  
`then`'s default-value depends on the `condition`:

* `pattern`: Simply the return value from the `match`, e.g. the entire match,
or, if there were capture groups, the first capture group.
* `function`: the return value of the function if it is either a string, or a
table (if there is no `then`, the function cannot return a table containing
something other than strings).
* `lambda`: Simply the first value returned by the lambda.

Examples:

* `match(n, "^ABC$", "A")` .
* `match(n, lambda._1:match(lambda._1:reverse()), "PALINDROME")` 

  ```lua
  s("trig", {
  	i(1), t":",
  	i(2), t"::",
  	m({1, 2}, l._1:match("^"..l._2.."$"), l._1:gsub("a", "e"))
  })
  ```


* ```lua
    s("extras1", {
      i(1), t { "", "" }, m(1, "^ABC$", "A")
    }),
  ```
  Inserts "A" if the node with jump-index `n` matches "ABC" exactly, nothing otherwise.

  <!-- panvimdoc-ignore-start -->
  
  ![extras1](https://user-images.githubusercontent.com/25300418/184359431-50f90599-3db0-4df0-a3a9-27013e663649.gif)
  
  <!-- panvimdoc-ignore-end -->

* ```lua
  s("extras2", {
    i(1, "INPUT"), t { "", "" }, m(1, l._1:match(l._1:reverse()), "PALINDROME")
  }),
  ```
  Inserts `"PALINDROME"` if i(1) contains a palindrome.

  <!-- panvimdoc-ignore-start -->

  ![extras2](https://user-images.githubusercontent.com/25300418/184359435-21e4de9f-c56b-4ee1-bff4-331b68e1c537.gif)

  <!-- panvimdoc-ignore-end -->
* ```lua
  s("extras3", {
    i(1), t { "", "" }, i(2), t { "", "" },
    m({ 1, 2 }, l._1:match("^" .. l._2 .. "$"), l._1:gsub("a", "e"))
  }),
  ```
  This inserts the text of the node with jump-index 1, with all occurences of
  `a` replaced with `e`, if the second insertNode matches the first exactly.

  <!-- panvimdoc-ignore-start -->

  ![extras3](https://user-images.githubusercontent.com/25300418/184359436-515ca1cc-207f-400d-98ba-39fa166e22e4.gif)

  <!-- panvimdoc-ignore-end -->

## Repeat

Inserts the text of the passed node.

`rep(node_reference)`
- `node_reference`, a single [`node-reference`](#node_reference).

```lua
s("extras4", { i(1), t { "", "" }, extras.rep(1) }),
```

<!-- panvimdoc-ignore-start -->

![extras4](https://user-images.githubusercontent.com/25300418/184359193-6525d60d-8fd8-4fbd-9d3f-e3e7d5a0259f.gif)

<!-- panvimdoc-ignore-end -->

## Partial

Evaluates a function on expand and inserts its' value.

`partial(fn, params...)`
- `fn`: any function
- `params`: varargs, any, will be passed to `fn`.

For example `partial(os.date, "%Y")` inserts the current year on expansion.


```lua
s("extras5", { extras.partial(os.date, "%Y") }),
```

<!-- panvimdoc-ignore-start -->

![extras5](https://user-images.githubusercontent.com/25300418/184359206-6c25fc3b-69e1-4529-9ebf-cb92148f3597.gif)

<!-- panvimdoc-ignore-end -->

## Nonempty
Inserts text if the referenced node doesn't contain any text.  
`nonempty(node_reference, not_empty, empty)`
- `node_reference`, a single [node-reference](#node_reference).  
- `not_empty`, `string`: inserted if the node is not empty.
- `empty`, `string`: inserted if the node is empty.

```lua
s("extras6", { i(1, ""), t { "", "" }, extras.nonempty(1, "not empty!", "empty!") }),
```

<!-- panvimdoc-ignore-start -->

![extras6](https://user-images.githubusercontent.com/25300418/184359213-79a71d1e-079c-454d-a092-c231ac5a98f9.gif)

<!-- panvimdoc-ignore-end -->

## Dynamic Lambda

Pretty much the same as lambda, it just inserts the resulting text as an
insertNode, and, as such, it can be quickly overridden.

`dynamic_lambda(jump_indx, lambda, node_references)`
- `jump_indx`, as usual, the jump-indx.

The remaining arguments carry over from lambda.

```lua
s("extras7", { i(1), t { "", "" }, extras.dynamic_lambda(2, l._1 .. l._1, 1) }),
```

<!-- panvimdoc-ignore-start -->

![extras7](https://user-images.githubusercontent.com/25300418/184359221-1f090895-bc59-44b0-a984-703bf8d278a3.gif)

<!-- panvimdoc-ignore-end -->

## FMT

Authoring snippets can be quite clunky, especially since every second node is
probably a `textNode`, inserting a small number of characters between two more
complicated nodes.  
`fmt` can be used to define snippets in a much more readable way. This is
achieved by borrowing (as the name implies) from `format`-functionality (our
syntax is very similar to
[python's](https://docs.python.org/3/library/stdtypes.html#str.format)).  
`fmt` accepts a string and a table of nodes. Each occurrence of a delimiter-pair
in the string is replaced by one node from the table, while text outside the
delimiters is turned into textNodes.

Simple example:

```lua
ls.add_snippets("all", {
  -- important! fmt does not return a snippet, it returns a table of nodes.
  s("example1", fmt("just an {iNode1}", {
    iNode1 = i(1, "example")
  })),
  s("example2", fmt([[
  if {} then
    {}
  end
  ]], {
    -- i(1) is at nodes[1], i(2) at nodes[2].
    i(1, "not now"), i(2, "when")
  })),
  s("example3", fmt([[
  if <> then
    <>
  end
  ]], {
    -- i(1) is at nodes[1], i(2) at nodes[2].
    i(1, "not now"), i(2, "when")
  }, {
    delimiters = "<>"
  })),
  s("example4", fmt([[
  repeat {a} with the same key {a}
  ]], {
    a = i(1, "this will be repeat")
  }, {
    repeat_duplicates = true
  }))
})
```

<!-- panvimdoc-ignore-start -->

![fmt](https://user-images.githubusercontent.com/25300418/184359228-d30df745-0fe8-49df-b28d-662e7eb050ec.gif)

<!-- panvimdoc-ignore-end -->

One important detail here is that the position of the delimiters does not, in
any way, correspond to the jump-index of the nodes!

`fmt(format:string, nodes:table of nodes, opts:table|nil) -> table of nodes`

* `format`: a string. Occurences of `{<somekey>}` ( `{,}` are customizable, more
  on that later) are replaced with `content[<somekey>]` (which should be a
  node), while surrounding text becomes `textNode`s.  
  To escape a delimiter, repeat it (`"{{"`).  
  If no key is given (`{}`) are numbered automatically:  
  `"{} ? {} : {}"` becomes `"{1} ? {2} : {3}"`, while
  `"{} ? {3} : {}"` becomes `"{1} ? {3} : {4}"` (the count restarts at each
  numbered placeholder).
  If a key appears more than once in `format`, the node in
  `content[<duplicate_key>]` is inserted for the first, and copies of it for
  subsequent occurences.
* `nodes`: just a table of nodes.
* `opts`: optional arguments:
  * `delimiters`: string, two characters. Change `{,}` to some other pair, e.g.
  	`"<>"`.
  * `strict`: Warn about unused nodes (default true).
  * `trim_empty`: remove empty (`"%s*"`) first and last line in `format`. Useful
  	when passing multiline strings via `[[]]` (default true).
  * `dedent`: remove indent common to all lines in `format`. Again, makes
  	passing multiline-strings a bit nicer (default true).
  * `repeat_duplicates`: repeat nodes when a key is reused instead of copying
        the node if it has a jump-index, refer to [jump-index](#jump-index) to
        know which nodes have a jump-index (default false).

There is also `require("luasnip.extras.fmt").fmta`. This only differs from `fmt`
by using angle-brackets (`<>`) as the default-delimiter.

## Conditions

This module (`luasnip.extras.condition`) contains function that can be passed to
a snippet's `condition` or `show_condition`. These are grouped accordingly into
`luasnip.extras.conditions.expand` and `luasnip.extras.conditions.show`:

**`expand`**:
- `line_begin`: only expand if the cursor is at the beginning of the line.

**`show`**:
- `line_end`: only expand at the end of the line.

`expand` contains, additionally, all conditions provided by `show`.

### Condition-Objects

`luasnip.extras.conditions` also contains condition-objects. These can, just
like functions, be passed to `condition` or `show_condition`, but can also be
combined with each other into logical expressions:

- `c1 + c2 -> c1 or c2`
- `c1 * c2 -> c1 and c2`
- `-c1 -> not c1`
- `c1 ^ c2 -> c1 xor(!=) c2`
- `c1 % c2 -> c1 xnor(==) c2`: This decision may seem weird, considering how
  there is an overload for the `==`-operator. Unfortunately, it's not possible
  to use this for our purposes (some info
  [here](https://github.com/L3MON4D3/LuaSnip/pull/612#issuecomment-1264487743)),
  so we decided to make use of a more obscure symbol (which will hopefully avoid
  false assumptions about its meaning).

This makes logical combinations of conditions very readable. Compare
```lua
condition = conditions.expand.line_end + conditions.expand.line_begin
```

with the more verbose

```lua
condition = function(...) return conditions.expand.line_end(...) or conditions.expand.line_begin(...) end
```

The conditions provided in `show` and `expand` are already condition-objects. To
create new ones, use
`require("luasnip.extras.conditions").make_condition(condition_fn)`


## On The Fly snippets

Sometimes it's desirable to create snippets tailored for exactly the current
situation. For example inserting repetitive, but just slightly different
invocations of some function, or supplying data in some schema.  
On The Fly-snippets enable exactly this usecase: they can be quickly created
and expanded, with as little disruption as possible.  

Since they should mainly fast to write, and don't necessarily need all bells and
whistles, they don't make use of lsp/textmate-syntax, but a more simplistic one:  

* `$anytext` denotes a placeholder (`insertNode`) with text "anytext". The text
  also serves as a unique key: if there are multiple placeholders with the same
  key, only the first will be editable, the others will just mirror it.  
* ... That's it. `$` can be escaped by preceding it with a second `$`, all other
  symbols will be interpreted literally.

There is currently only one way to expand On The Fly-snippets:  
`require('luasnip.extras.otf').on_the_fly("<some-register>")` will interpret
whatever text is in the register `<some-register>` as a snippet, and expand it
immediately.  
The idea behind this mechanism is that it enables a very immediate way of
supplying and retrieving (expanding) the snippet: write the snippet-body into
the buffer, cut/yank it into some register, and call `on_the_fly("<register>")`
to expand the snippet.  

Here's one set of example-keybindings:

```vim
" in the first call: passing the register is optional since `on_the_fly`
" defaults to the unnamed register, which will always contain the previously cut
" text.
vnoremap <c-f>  "ec<cmd>lua require('luasnip.extras.otf').on_the_fly("e")<cr>
inoremap <c-f>  <cmd>lua require('luasnip.extras.otf').on_the_fly("e")<cr>
```

Obviously, `<c-f>` is arbritary, and can be changed to any other key-combo.
Another interesting application is allowing multiple on the fly-snippets at the
same time, by retrieving snippets from multiple registers:
```vim
" For register a
vnoremap <c-f>a  "ac<cmd>lua require('luasnip.extras.otf').on_the_fly()<cr>
inoremap <c-f>a  <cmd>lua require('luasnip.extras.otf').on_the_fly("a")<cr>


" For register b
vnoremap <c-f>a  "bc<cmd>:lua require('luasnip.extras.otf').on_the_fly()<cr>
inoremap <c-f>b  <cmd>lua require('luasnip.extras.otf').on_the_fly("b")<cr>
```

<!-- panvimdoc-ignore-start -->

![otf](https://user-images.githubusercontent.com/25300418/184359312-8e368393-7be3-4dc4-ae08-1ff1bf17b309.gif)

<!-- panvimdoc-ignore-end -->

## Select_choice

It's possible to leverage `vim.ui.select` for selecting a choice directly,
without cycling through the available choices.  
All that is needed for this is calling
`require("luasnip.extras.select_choice")`, most likely via some keybind, e.g.

```vim
inoremap <c-u> <cmd>lua require("luasnip.extras.select_choice")()<cr>
```
while inside a choiceNode.  
The `opts.kind` hint for `vim.ui.select` will be set to `luasnip`.

<!-- panvimdoc-ignore-start -->

![select_choice](https://user-images.githubusercontent.com/25300418/184359342-c8d79d50-103c-44b7-805f-fe75294e62df.gif)

<!-- panvimdoc-ignore-end -->

## filetype_functions

Contains some utility-functions that can be passed to the `ft_func` or
`load_ft_func`-settings.

* `from_filetype`: the default for `ft_func`. Simply returns the filetype(s) of
  the buffer.
* `from_cursor_pos`: uses treesitter to determine the filetype at the cursor.
  With that, it's possible to expand snippets in injected regions, as long as
  the treesitter-parser supports them.
  If this is used in conjuction with `lazy_load`, extra care must be taken that
  all the filetypes that can be expanded in a given buffer are also returned by
  `load_ft_func` (otherwise their snippets may not be loaded).
  This can easily be achieved with `extend_load_ft`.
* `extend_load_ft`: `fn(extend_ft:map) -> fn`
  A simple solution to the problem described above is loading more filetypes
  than just that of the target-buffer when `lazy_load`ing. This can be done
  ergonomically via `extend_load_ft`: calling it with a table where the keys are
  filetypes, and the values are the filetypes that should be loaded additionaly
  returns a function that can be passed to `load_ft_func` and takes care of
  extending the filetypes properly.

  ```lua
  ls.setup({
  	load_ft_func =
  		-- Also load both lua and json when a markdown-file is opened,
  		-- javascript for html.
  		-- Other filetypes just load themselves.
  		require("luasnip.extras.filetype_functions").extend_load_ft({
  			markdown = {"lua", "json"},
  			html = {"javascript"}
  		})
  })
  ```

## POSTFIX SNIPPET

Postfix snippets, famously used in 
[rust analyzer](https://rust-analyzer.github.io/) and various IDEs, are a type
of snippet, which alters text before the snippets trigger. While these
can be implemented using regTrig snippets, this helper makes the process easier
in most cases.

The simplest example, which surrounds the text preceeding the `.br` with
brackets `[]`, looks like:

```lua

      postfix(".br", {
              f(function(_, parent)
                    return "[" .. parent.snippet.env.POSTFIX_MATCH .. "]"
              end, {}),
      })
```

<!-- panvimdoc-ignore-start -->

![postfix](https://user-images.githubusercontent.com/25300418/184359322-d8547259-653e-4ada-86e8-666da2c52010.gif)

<!-- panvimdoc-ignore-end -->

and is triggered with `xxx.br` and expands to `[xxx]`.

Note the `parent.snippet.env.POSTFIX_MATCH` in the function node. This is additional
field generated by the postfix snippet. This field is generated by extracting
the text matched (using a configurable matching string, see below) from before
the trigger. In the case above, the field would equal `"xxx"`. This is also
usable within dynamic nodes.

This field can also be used within lambdas and dynamic nodes.

```lua
      postfix(".br", {
              l("[" .. l.POSTFIX_MATCH .. "]"),
      })
```

```lua
	postfix(".brd", {
	  d(1, function (_, parent)
	    return sn(nil, {t("[" .. parent.env.POSTFIX_MATCH .. "]")})
	  end)
	}),
```

<!-- panvimdoc-ignore-start -->

![postfix2](https://user-images.githubusercontent.com/25300418/184359323-1b250b6d-7b23-43a3-846f-b6cc2c9df9fc.gif)

<!-- panvimdoc-ignore-end -->

The arguments to `postfix` are identical to the arguments to `s` but with a few
extra options.

The first argument can be either a string or a table. If it is a string, that
string will act as the trigger, and if it is a table it has the same valid keys
as the table in the same position for `s` except:

- `wordTrig`: This key will be ignored if passed in, as it must always be
    false for postfix snippets.
- `match_pattern`: The pattern that the line before the trigger is matched
    against. The default match pattern is `"[%w%.%_%-]+$"`. Note the `$`. This
    matches since only the line _up until_ the beginning of the trigger is
    matched against the pattern, which makes the character immediately
    preceeding the trigger match as the end of the string.

Some other match strings, including the default, are available from the postfix
module. `require("luasnip.extras.postfix).matches`:

- `default`: [%w%.%_%-%"%']+$
- 'line': `^.+$`

The second argument is identical to the second argument for `s`, that is, a
table of nodes.

The optional third argument is the same as the third (`opts`) argument to the
`s` function, but with one difference:

The postfix snippet works using a callback on the pre_expand event of the
snippet. If you pass a callback on the pre_expand event (structure example
below) it will get run after the builtin callback. This means that your
callback will have access to the `POSTFIX_MATCH` field as well.

```lua

      {
        callbacks = {
              [-1] = {
                      [events.pre_expand] = function(snippet, event_args)
                          -- function body to match before the dot
                          -- goes here
                       end
                      }
                    }
        }
```

## Snippet List

```lua
local sl = require("luasnip.extras.snippet_list")
```

Makes an `open` function available to use to open currently available snippets
in a different buffer/window/tab.

`sl.open(opts:table|nil)`

* `opts`: optional arguments:
    * `snip_info`: `snip_info(snippet) -> table representation of snippet`
    * `printer`: `printer(snippets:table) -> any`
    * `display`: `display(snippets:any)`

Benefits include: syntax highlighting, searching, and customizability.

Simple Example:
```lua
sl.open()
```

<!-- panvimdoc-ignore-start -->

![default](https://user-images.githubusercontent.com/43832900/204893019-3a83d6bc-9e01-4750-bdf4-f6af967af807.png)

<!-- panvimdoc-ignore-end -->

Customization Examples:
```lua
-- making our own snip_info
local function snip_info(snippet)
	return { name = snippet.name }
end

-- using it
sl.open({snip_info = snip_info})
```

<!-- panvimdoc-ignore-start -->

![snip_info](https://user-images.githubusercontent.com/43832900/204893340-c7296a70-370a-4ad3-8997-23887f311b74.png)

<!-- panvimdoc-ignore-end -->

```lua
-- making our own printer
local function printer(snippets)
    local res = ""

    for ft, snips in pairs(snippets) do
        res = res .. ft .. "\n"
        for _, snip in pairs(snips) do
            res = res .. "    " .. "Name: " .. snip.name .. "\n"
            res = res .. "    " .. "Desc: " .. snip.description[1] .. "\n"
            res = res .. "    " .. "Trigger: " .. snip.trigger .. "\n"
            res = res .. "    ----" .. "\n"
        end
    end

    return res
end


-- using it
sl.open({printer = printer})
```

<!-- panvimdoc-ignore-start -->

![printer](https://user-images.githubusercontent.com/43832900/204893406-4fc397e2-6d42-43f3-b52d-59ac448e764c.png)

<!-- panvimdoc-ignore-end -->

```lua
-- making our own display
local function display(printer_result)
    -- right vertical split
    vim.cmd("botright vnew")

    -- get buf and win handle
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()

    -- setting window and buffer options
    vim.api.nvim_win_set_option(win, "foldmethod", "manual")
    vim.api.nvim_buf_set_option(buf, "filetype", "javascript")

    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "buflisted", false)

    vim.api.nvim_buf_set_name(buf, "Custom Display buf " .. buf)

    -- dump snippets
    local replacement = vim.split(printer_result)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, replacement)
end

-- using it
sl.open({display = display})
```

<!-- panvimdoc-ignore-start -->

![display](https://user-images.githubusercontent.com/43832900/205133425-a3fffa1c-bbec-4aea-927b-5faed14856d7.png)

<!-- panvimdoc-ignore-end -->

There is a **caveat** with implementing your own printer and/or display
function. The **default** behavior for the printer function is to return a
string representation of the snippets. The display function uses the results
from the printer function, therefore by **default** the display function is
expecting that result to be a string.

This doesn't have to be the case however. You can for example implement your
own printer function that returns a table representation of the snippets
**but** you would have to then implement your own display function or some
other function in order to stringify this result.

An `options` table is available which has functionality in it that can be used
to customize 'common' settings.

* `sl.options`: options table:
    * `display`: `display(opts:table|nil) -> function(printer_result:string)`

You can see from the example above that making a custom display is a fairly
involved process. What if you just wanted to change a buffer option like the
name or just the filetype? This is where `sl.options.display` comes in. It
allows you to customize buffer and window options while keeping the default
behavior.

`sl.options.display(opts:table|nil) -> function(printer_result:string)`

* `opts`: optional arguments:
    * `win_opts`: `table which has a {window_option = value} form`
    * `buf_opts`: `table which has a {buffer_option = value} form`
    * `get_name`: `get_name(buf) -> string`

Let's recreate the custom display example above:
```lua
-- keeping the default display behavior but modifying window/buffer
local modified_default_display = sl.options.display({
        buf_opts = {filetype = "javascript"},
        win_opts = {foldmethod = "manual"},
        get_name = function(buf) return "Custom Display buf " .. buf end
    })

-- using it
sl.open({display = modified_default_display})
```

<!-- panvimdoc-ignore-start -->

![modified display](https://user-images.githubusercontent.com/43832900/205133441-f4363bab-bdab-4c60-af9d-7285d59eca03.png)

<!-- panvimdoc-ignore-end -->

# EXTEND_DECORATOR

Most of luasnip's functions have some arguments to control their behaviour.  
Examples include `s`, where `wordTrig`, `regTrig`, ... can be set in the first
argument to the function, or `fmt`, where the delimiter can be set in the third
argument.  
This is all good and well, but if these functions are often used with
non-default settings, it can become cumbersome to always explicitly set them.

This is where the `extend_decorator` comes in:  
It can be used to create decorated functions which always extend the arguments
passed directly with other, previously defined ones.  
An example:
```lua
local fmt = require("luasnip.extras.fmt").fmt

fmt("{}", {i(1)}) -- -> list of nodes, containing just the i(1).

-- when authoring snippets for some filetype where `{` and `}` are common, they
-- would always have to be escaped in the format-string. It might be preferable
-- to use other delimiters, like `<` and `>`.

fmt("<>", {i(1)}, {delimiters = "<>"}) -- -> same as above.

-- but it's quite annoying to always pass the `{delimiters = "<>"}`.

-- with extend_decorator:
local fmt_angle = ls.extend_decorator.apply(fmt, {delimiters = "<>"})
fmt_angle("<>", {i(1)}) -- -> same as above.

-- the same also works with other functions provided by luasnip, for example all
-- node/snippet-constructors and `parse_snippet`.
```

`extend_decorator.apply(fn, ...)` requires that `fn` is previously registered
via `extend_decorator.register`.  
(This is not limited to luasnip's functions!)  
(although, for usage outside of luasnip, best copy the source-file
`/lua/luasnip/util/extend_decorator.lua`).

`register(fn, ...)`:

* `fn`: the function.
* `...`: any number of tables. Each specifies how to extend an argument of `fn`.
  The tables accept:
  * arg_indx, `number` (required): the position of the parameter to override.
  * extend, `fn(arg, extend_value) -> effective_arg` (optional): this function
    is used to extend the args passed to the decorated function.
    It defaults to a function which just extends the the arg-table with the
    extend-table (accepts `nil`).
    This extend-behaviour is adaptable to accomodate `s`, where the first
    argument may be string or table.

`apply(fn, ...) -> decorated_fn`:

* `fn`: the function to decorate.
* `...`: The values to extend with. These should match the descriptions passed
  in `register` (the argument first passed to `register` will be extended with
  the first value passed here).

One more example for registering a new function:
```lua
local function somefn(arg1, arg2, opts1, opts2)
	... -- not important
end

-- note the reversed arg_indx!!
extend_decorator.register(somefn, {arg_indx=4}, {arg_indx=3})
local extended = extend_decorator.apply(somefn,
	{key = "opts2 is extended with this"},
	{key = "and opts1 with this"})
extended(...)
```

# LSP-SNIPPETS

Luasnip is capable of parsing lsp-style snippets using
`ls.parser.parse_snippet(context, snippet_string, opts)`:
```lua
ls.parser.parse_snippet({trig = "lsp"}, "$1 is ${2|hard,easy,challenging|}")
```

<!-- panvimdoc-ignore-start -->

![lsp](https://user-images.githubusercontent.com/25300418/184359304-eb9c9eb4-bd38-4db9-b412-792391e9c21d.gif)

<!-- panvimdoc-ignore-end -->

`context` can be:
  - `string|table`: treated like the first argument to `ls.s`, `parse_snippet`
    returns a snippet.
  - `number`: `parse_snippet` returns a snippetNode, with the position
    `context`.
  - `nil`: `parse_snippet` returns a flat table of nodes. This can be used
    like `fmt`.

Nested placeholders(`"${1:this is ${2:nested}}"`) will be turned into
choiceNode's with:
  - the given snippet(`"this is ${1:nested}"`) and
  - an empty insertNode

<!-- panvimdoc-ignore-start -->

![lsp2](https://user-images.githubusercontent.com/25300418/184359306-c669d3fa-7ae5-4c07-b11a-34ae8c4a17ac.gif)

<!-- panvimdoc-ignore-end -->

This behaviour can be modified by changing `parser_nested_assembler` in
`ls.setup()`.


Luasnip will also modify some snippets it's incapable of representing
accurately:
  - if the `$0` is a placeholder with something other than just text inside
  - if the `$0` is a choice
  - if the `$0` is not an immediate child of the snippet (it could be inside a
    placeholder: `"${1: $0 }"`)

To remedy those incompatibilities, the invalid `$0` will be replaced with a
tabstop/placeholder/choice which will be visited just before the new `$0`. This
new `$0` will be inserted at the (textually) earliest valid position behind the
invalid `$0`.

`opts` can contain the following keys:
  - `trim_empty`: boolean, remove empty lines from the snippet. Default true.
  - `dedent`: boolean, remove common indent from the snippet's lines.
    Default true.

Both `trim_empty` and `dedent` will be disabled for snippets parsed via
`ls.lsp_expand`: it might prevent correct expansion of snippets sent by lsp.

## Snipmate Parser

It is furthermore possible to parse snipmate-snippets (this includes support for
vimscript-evaluation!!)  
Snipmate-snippets have to be parsed with a different function,
`ls.parser.parse_snipmate`:
```lua
ls.parser.parse_snipmate("year", "The year is `strftime('%Y')`")
```

`parse_snipmate` accepts the same arguments as `parse_snippet`, only the
snippet-body is parsed differently.

## Transformations

To apply
[Variable/Placeholder-transformations](https://code.visualstudio.com/docs/editor/userdefinedsnippets#_variable-transforms),
luasnip needs to apply ECMAScript regexes.
This is implemented by relying on [`jsregexp`](https://github.com/kmarius/jsregexp).  
The easiest, but potentially error-prone way to install it is by calling `make
install_jsregexp` in the repo-root.
This process can be automated by `packer.nvim`:
```lua
use { "L3MON4D3/LuaSnip", run = "make install_jsregexp" }
```
If this fails, first open an issue :P, and then try installing the
`jsregexp`-luarock. This is also possible via 
`packer.nvim`, although actual usage may require a small workaround, see
[here](https://github.com/wbthomason/packer.nvim/issues/593) or
[here](https://github.com/wbthomason/packer.nvim/issues/358).  

Alternatively, `jsregexp` can be cloned locally, `make`d, and the resulting
`jsregexp.so` placed in some place where nvim can find it (probably
`~/.config/nvim/lua/`).

If `jsregexp` is not available, transformation are replaced by a simple copy.

# VARIABLES

All `TM_something`-variables are supported with two additions:
`LS_SELECT_RAW` and `LS_SELECT_DEDENT`. These were introduced because
`TM_SELECTED_TEXT` is designed to be compatible with vscodes' behavior, which
can be counterintuitive when the snippet can be expanded at places other than
the point where selection started (or when doing transformations on selected text).
Besides those we also provide `LS_TRIGGER` which contains the trigger of the snippet,
and  `LS_CAPTURE_n` (where n is a positive integer) that contains the n-th capture
when using a regex with capture groups as `trig` in the snippet definition.

All variables can be used outside of lsp-parsed snippets as their values are
stored in a snippets' `snip.env`-table:
```lua
s("selected_text", f(function(args, snip)
  local res, env = {}, snip.env
  table.insert(res, "Selected Text (current line is " .. env.TM_LINE_NUMBER .. "):")
  for _, ele in ipairs(env.LS_SELECT_RAW) do table.insert(res, ele) end
  return res
end, {}))
```

To use any `*SELECT*` variable, the `store_selection_keys` must be set via
`require("luasnip").config.setup({store_selection_keys="<Tab>"})`. In this case,
hitting `<Tab>` while in Visualmode will populate the `*SELECT*`-vars for the next
snippet and then clear them.

<!-- panvimdoc-ignore-start -->

![variable](https://user-images.githubusercontent.com/25300418/184359360-17cc75cd-a8a0-4385-a6cb-8fa321c14558.gif)

<!-- panvimdoc-ignore-end -->

## Environment Namespaces

You can also add your own variables by using the `ls.env_namespace(name, opts)` where:

* `name`: `string` the names the namespace, can't contain the character "_"
* `opts` is a table containing (in every case `EnvVal` is the same as `string|list[string]`:
    * `vars`: `(fn(name:string)->EnvVal) | map[string, EnvVal]`
    Is a function that receives a string and returns a value for the var with that name
    or a table from var name to a value
    (in this case, if the value is a function it will be executed  lazily once per snippet expansion).
    * `init`: `fn(info: table)->map[string, EnvVal]`  Returns
        a table of variables that will set to the environment of the snippet on expansion,
        use this for vars that have to be calculated in that moment or that depend on each other.
        The `info` table argument contains `pos` (0-based position of the cursor on expansion),
        the `trigger` of the snippet and the `captures` list.
    * `eager`: `list[string]` names of variables that will be taken from `vars` and appended eagerly (like those in init)
    * `multiline_vars`: `(fn(name:string)->bool)|map[sting, bool]|bool|string[]` Says if certain vars are a table or just a string,
        can be a function that get's the name of the var and returns true if the var is a key,
        a list of vars that are tables or a boolean for the full namespace, it's false by default. Refer to
        [issue#510](https://github.com/L3MON4D3/LuaSnip/issues/510#issuecomment-1209333698) for more information.

The four fields of `opts` are optional but you need to provide either `init` or  `vars`, and `eager` can't be without `vars`.
Also you can't use namespaces that override default vars.


A simple example to make it more clear:

```lua
local function random_lang()
    return ({"LUA", "VIML", "VIML9"})[math.floor(math.random()/2 + 1.5)]
end

ls.env_namespace("MY", {vars={ NAME="LuaSnip",  LANG=random_lang }})

-- then you can use  $MY_NAME and $MY_LANG in your snippets

ls.env_namespace("SYS", {vars=os.getenv, eager={"HOME"}})

-- then you can use  $SYS_HOME which was eagerly initialized but also $SYS_USER (or any other system environment var) in your snippets

lsp.env_namespace("POS", {init=function(info) return {VAL=vim.inspect(info.pos)} end})

-- then you can use  $POS_VAL in your snippets

s("custom_env", d(1, function(args, parent)
  local env = parent.snippet.env
  return sn(nil, t {
    "NAME: " .. env.MY_NAME,
    "LANG: " .. env.MY_LANG,
    "HOME: " .. env.SYS_HOME,
    "USER: " .. env.SYS_USER,
    "VAL: " .. env.POS_VAL
  })
end, {}))
```

<!-- panvimdoc-ignore-start -->

![custom_variable](https://user-images.githubusercontent.com/25300418/184359382-2b2a357b-37a6-4cc4-9c8f-930f26457888.gif)

<!-- panvimdoc-ignore-end -->

## LSP-Variables

All variables, even ones added via `env_namespace`, can be accessed in
lsp-snippets as `$VAR_NAME`.

The lsp-spec states:

----

With `$name` or `${name:default}` you can insert the value of a variable.  
When a variable isn’t set, its default or the empty string is inserted.
When a variable is unknown (that is, its name isn’t defined) the name of the variable is inserted and it is transformed into a placeholder.

----

The above necessiates a differentiation between `unknown` and `unset` variables:

For Luasnip, a variable `VARNAME` is `unknown` when `env.VARNAME` returns `nil` and `unset`
if it returns an empty string.

Consider this when adding env-variables which might be used in lsp-snippets.

# LOADERS

Luasnip is capable of loading snippets from different formats, including both
the well-established vscode- and snipmate-format, as well as plain lua-files for
snippets written in lua

All loaders share a similar interface:
```lua
require("luasnip.loaders.from_{vscode,snipmate,lua}").{lazy_,}load(opts:table|nil)
```

where `opts` can contain the following keys:

- `paths`: List of paths to load. Can be a table, or a single
  comma-separated string.
  The paths may begin with `~/` or `./` to indicate that the path is
  relative to your `$HOME` or to the directory where your `$MYVIMRC` resides
  (useful to add your snippets).  
  If not set, `runtimepath` is searched for
  directories that contain snippets. This procedure differs slightly for
  each loader:
  - `lua`: the snippet-library has to be in a directory named
    `"luasnippets"`.
  - `snipmate`: similar to lua, but the directory has to be `"snippets"`.
  - `vscode`: any directory in `runtimepath` that contains a
    `package.json` contributing snippets.
- `exclude`: List of languages to exclude, empty by default.
- `include`: List of languages to include, includes everything by default.
- `{override,default}_priority`: These keys are passed straight to the
  [`add_snippets`](#api-reference)-calls and can therefore change the priority
  of snippets loaded from some colletion (or, in combination with
  `{in,ex}clude`, only some of its snippets).

While `load` will immediately load the snippets, `lazy_load` will defer loading until
the snippets are actually needed (whenever a new buffer is created, or the
filetype is changed luasnip actually loads `lazy_load`ed snippets for the
filetypes associated with this buffer. This association can be changed by
customizing `load_ft_func` in `setup`: the option takes a function that, passed
a `bufnr`, returns the filetypes that should be loaded (`fn(bufnr) -> filetypes
(string[])`)).

All of the loaders support reloading, so simply editing any file contributing
snippets will reload its snippets (only in the session the file was edited in,
we use `BufWritePost` for reloading, not some lower-level mechanism).

For easy editing of these files, Luasnip provides a [`vim.ui.select`-based
dialog](#edit_snippets) where first the filetype, and then the file can be
selected.

## Troubleshooting

* Luasnip uses `all` as the global filetype. As most snippet collections don't
  explicitly target luasnip, they may not provide global snippets for this
  filetype, but another, like `_` (`honza/vim-snippets`).
  In these cases, it's necessary to extend luasnip's global filetype with the
  collection's global filetype:
  ```lua
  ls.filetype_extend("all", { "_" })
  ```

  In general, if some snippets don't show up when loading a collection, a good
  first step is checking the filetype luasnip is actually looking into (print
  them for the current buffer via `:lua
  print(vim.inspect(require("luasnip").get_snippet_filetypes()))`), against the
  one the missing snippet is provided for (in the collection).  
  If there is indeed a mismatch, `filetype_extend` can be used to also search
  the collection's filetype:
  ```lua
  ls.filetype_extend("<luasnip-filetype>", { "<collection-filetype>" })
  ```

* As we only load `lazy_load`ed snippet on some events, `lazy_load` will
  probably not play nice when a non-default `ft_func` is used: if it depends on
  e.g. the cursor-position, only the filetypes for the cursor-position when the
  `lazy_load`-events are triggered will be loaded. Check
  [filetype_function's `extend_load_ft`](#filetype_functions) for a solution.

## VSCODE

As a reference on the structure of these snippet-libraries, see
[`friendly-snippets`](https://github.com/rafamadriz/friendly-snippets).

We support a small extension: snippets can contain luasnip-specific options in
the `luasnip`-table:
```json
"example1": {
	"prefix": "options",
	"body": [
		"whoa! :O"
	],
	"luasnip": {
		"priority": 2000,
		"autotrigger": true,
		"wordTrig": false
	}
}
```

**Example**:

`~/.config/nvim/my_snippets/package.json`:
```json
{
	"name": "example-snippets",
	"contributes": {
		"snippets": [
			{
				"language": [
					"all"
				],
				"path": "./snippets/all.json"
			},
			{
				"language": [
					"lua"
				],
				"path": "./lua.json"
			}
		]
	}
}
```
`~/.config/nvim/my_snippets/snippets/all.json`:
```json
{
	"snip1": {
		"prefix": "all1",
		"body": [
			"expands? jumps? $1 $2 !"
		]
	},
	"snip2": {
		"prefix": "all2",
		"body": [
			"multi $1",
			"line $2",
			"snippet$0"
		]
	}
}
```

`~/.config/nvim/my_snippets/lua.json`:
```json
{
	"snip1": {
		"prefix": "lua",
		"body": [
			"lualualua"
		]
	}
}
```
This collection can be loaded with any of
```lua
-- don't pass any arguments, luasnip will find the collection because it is
-- (probably) in rtp.
require("luasnip.loaders.from_vscode").lazy_load()
-- specify the full path...
require("luasnip.loaders.from_vscode").lazy_load({paths = "~/.config/nvim/my_snippets"})
-- or relative to the directory of $MYVIMRC
require("luasnip.loaders.from_vscode").load({paths = "./my_snippets"})
```
## SNIPMATE

Luasnip does not support the full snipmate format: Only `./{ft}.snippets` and
`./{ft}/*.snippets` will be loaded. See
[honza/vim-snippets](https://github.com/honza/vim-snippets) for lots of
examples.

Like vscode, the snipmate-format is also extended to make use of some of
luasnips more advanced capabilities:
```snippets
priority 2000
autosnippet options
	whoa :O
```

**Example**:

`~/.config/nvim/snippets/c.snippets`:
```snippets
# this is a comment
snippet c c-snippet
	c!
```

`~/.config/nvim/snippets/cpp.snippets`:
```snippets
extends c

snippet cpp cpp-snippet
	cpp!
```

This can, again, be loaded with any of 
```lua
require("luasnip.loaders.from_snipmate").load()
-- specify the full path...
require("luasnip.loaders.from_snipmate").lazy_load({paths = "~/.config/nvim/snippets"})
-- or relative to the directory of $MYVIMRC
require("luasnip.loaders.from_snipmate").lazy_load({paths = "./snippets"})
```

Stuff to watch out for:

* Using both `extends <ft2>` in `<ft1>.snippets` and
  `ls.filetype_extend("<ft1>", {"<ft2>"})` leads to duplicate snippets.
* `${VISUAL}` will be replaced by `$TM_SELECTED_TEXT` to make the snippets
  compatible with luasnip
* We do not implement eval using \` (backtick). This may be implemented in the
  future.

## LUA

Instead of adding all snippets via `add_snippets`, it's possible to store them
in separate files and load all of those.  
The file-structure here is exactly the supported snipmate-structure, e.g.
`<ft>.lua` or `<ft>/*.lua` to add snippets for the filetype `<ft>`.  

There are two ways to add snippets:

* the files may return two lists of snippets, the snippets in the first are all
  added as regular snippets, while the snippets in the second will be added as
  autosnippets (both are the defaults, if a snippet defines a different
  `snippetType`, that will have preference)
* snippets can also be appended to the global (only for these files! They are not
  visible anywhere else) tables `ls_file_snippets` and `ls_file_autosnippets`.
  This can be combined with a custom `snip_env` to define and add snippets with
  one function-call:
  ```lua
  ls.setup({
  	snip_env = {
  		s = function(...)
  			local snip = ls.s(...)
  			-- we can't just access the global `ls_file_snippets`, since it will be
  			-- resolved in the environment of the scope in which it was defined.
  			table.insert(getfenv(2).ls_file_snippets, snip)
  		end,
  		parse = function(...)
  			local snip = ls.parser.parse_snippet(...)
  			table.insert(getfenv(2).ls_file_snippets, snip)
  		end,
  		-- remaining definitions.
  		...
  	},
  	...
  })
  ```
  This is more flexible than the previous approach since the snippets don't have
  to be collected, they just have to be defined using the above `s` and `parse`.

As defining all of the snippet-constructors (`s`, `c`, `t`, ...) in every file
is rather cumbersome, luasnip will bring some globals into scope for executing
these files.
By default, the names from [`luasnip.config.snip_env`][snip-env-src] will be used, but it's
possible to customize them by setting `snip_env` in `setup`.  

[snip-env-src]: https://github.com/L3MON4D3/LuaSnip/blob/master/lua/luasnip/config.lua#L122-L147

**Example**:

`~/snippets/all.lua`:
```lua
return {
	s("trig", t("loaded!!"))
}
```
`~/snippets/c.lua`:
```lua
return {
	s("ctrig", t("also loaded!!"))
}, {
	s("autotrig", t("autotriggered, if enabled"))
}
```

Load via 
```lua
require("luasnip.loaders.from_lua").load({paths = "~/snippets"})
```

## EDIT_SNIPPETS

To easily edit snippets for the current session, the files loaded by any loader
can be quickly edited via
`require("luasnip.loaders").edit_snippet_files(opts:table|nil)`  
When called, it will open a `vim.ui.select`-dialog to select first a filetype,
and then (if there are multiple) the associated file to edit.

<!-- panvimdoc-ignore-start -->

![edit-select](https://user-images.githubusercontent.com/25300418/184359412-e6a1238c-d733-411c-b05d-8334ea993fbf.gif)

<!-- panvimdoc-ignore-end -->

`opts` contains three settings:

* `format`: `fn(file:string, source_name:string) -> string|nil`  
  `file` is simply the path to the file, `source_name` is one of `"lua"`,
  `"snipmate"` or `"vscode"`.  
  If a string is returned, it is used as the title of the item, `nil` on the
  other hand will filter out this item.  
  The default simply replaces some long strings (packer-path and config-path)
  in `file` with shorter, symbolic names (`"$PLUGINS"`, `"$CONFIG"`), but
  this can be extended to
  * filter files from some specific source/path
  * more aggressively shorten paths using symbolic names, e.g.
  	`"$FRIENDLY_SNIPPETS"`.  
  	Example: hide the `*.lua` snippet files, and shorten the path with `$LuaSnip`:
    ```lua
    require "luasnip.loaders" .edit_snippet_files {
      format = function(file, source_name)
        if source_name == "lua" then return nil
        else return file:gsub("/root/.config/nvim/luasnippets", "$LuaSnip")
        end
      end
    }
    ```
	<!-- panvimdoc-ignore-start -->

    ![edit-select-format](https://user-images.githubusercontent.com/25300418/184359420-3bc22d67-1f90-49d9-ac4e-3ea2524bcf0d.gif)

	<!-- panvimdoc-ignore-end -->

* `edit`: `fn(file:string)` This function is supposed to open the file for
  editing. The default is a simple `vim.cmd("edit " .. file)` (replace the
  current buffer), but one could open the file in a split, a tab, or a floating
  window, for example.
* `extend`: `fn(ft:string, ft_paths:string[]) -> (string,string)[]`  
  This function can be used to create additional choices for the file-selection.

  * `ft`: The filetype snippet-files are queried for.
  * `ft_paths`: list of paths to the known snippet files. 

  The function should return a list of `(string,string)`-tuples. The first of
  each pair is the label that will appear in the selection-prompt, and the
  second is the path that will be passed to the `edit()` function if that item
  was selected.

  This can be used to create a new snippet-file for the current filetype:
```lua
require("luasnip.loaders").edit_snippet_files {
  extend = function(ft, paths)
    if #paths == 0 then
      return {
        { "$CONFIG/" .. ft .. ".snippets",
          string.format("%s/%s.snippets", <PERSONAL_SNIPPETS_FOLDER>, ft) }
      }
    end

    return {}
  end
}
```

One comfortable way to call this function is registering it as a command:
```vim
command! LuaSnipEdit :lua require("luasnip.loaders").edit_snippet_files()
```

# SNIPPETPROXY

`SnippetProxy` is used internally to alleviate the upfront-cost of
loading snippets from e.g. a snipmate-library or a vscode-package. This is
achieved by only parsing the snippet on expansion, not immediately after reading
it from some file.
`SnippetProxy` may also be used from lua directly, to get the same benefits:

This will parse the snippet on startup...
```lua
ls.parser.parse_snippet("trig", "a snippet $1!")
```

... and this will parse the snippet upon expansion.
```lua
local sp = require("luasnip.nodes.snippetProxy")
sp("trig", "a snippet $1")
```

`sp(context, body, opts) -> snippetProxy`

- `context`: exactly the same as the first argument passed to `ls.s`.
- `body`: the snippet-body.
- `opts`: accepts the same `opts` as `ls.s`, with some additions:
  - `parse_fn`: the function for parsing the snippet. Defaults to
    `ls.parser.parse_snippet` (the parser for lsp-snippets), an alternative is
    the parser for snipmate-snippets (`ls.parser.parse_snipmate`).

# EXT\_OPTS

`ext_opts` can be used to set the `opts` (see `nvim_buf_set_extmark`) of the
extmarks used for marking node-positions, either globally, per-snippet or
per-node.
This means that they allow highlighting the text inside of nodes, or adding
virtual text to the line the node begins on.

This is an example for the `node_ext_opts` used to set `ext_opts` of single nodes:
```lua
local ext_opts = {
	-- these ext_opts are applied when the node is active (e.g. it has been
	-- jumped into, and not out yet).
	active = 
	-- this is the table actually passed to `nvim_buf_set_extmark`.
	{
		-- highlight the text inside the node red.
		hl_group = "GruvboxRed"
	},
	-- these ext_opts are applied when the node is not active, but
	-- the snippet still is.
	passive = {
		-- add virtual text on the line of the node, behind all text.
		virt_text = {{"virtual text!!", "GruvboxBlue"}}
	},
	-- visited or unvisited are applied when a node was/was not jumped into.
	visited = {
		hl_group = "GruvboxBlue"
	},
	unvisited = {
		hl_group = "GruvboxGreen"
	},
	-- and these are applied when both the node and the snippet are inactive.
	snippet_passive = {}
}

...

s("trig", {
	i(1, "text1", {
		node_ext_opts = ext_opts
	}),
	i(2, "text2", {
		node_ext_opts = ext_opts
	})
})
```

<!-- panvimdoc-ignore-start -->

![ext_opt](https://user-images.githubusercontent.com/25300418/184359424-f3ae2e85-7863-437b-b360-0e3794c8fa1b.gif)

<!-- panvimdoc-ignore-end -->

In the above example the text inside the insertNodes is higlighted in green if
they were not yet visited, in blue once they were, and red while they are.  
The virtual text "virtual text!!" is visible as long as the snippet is active.

To make defining `ext_opts` less verbose, more specific states inherit from less
specific ones:

- `passive` inherits from `snippet_passive`
- `visited` and `unvisited` from `passive`
- `active` from `visited`

<!-- panvimdoc-ignore-start -->

```mermaid
flowchart TD
	visited --> active
	passive --> visited
	passive --> unvisited
	snippet_passive --> passive
```

<!-- panvimdoc-ignore-end -->

To disable a key from a less specific state, it has to be explicitly set to its
default, e.g. to disable highlighting inherited from `passive` when the node is
`active`, `hl_group` should be set to `None`.

---

As stated earlier, these `ext_opts` can also be applied globally or for an
entire snippet. For this it's necessary to specify which kind of node a given
set of `ext_opts` should be applied to:

```lua
local types = require("luasnip.util.types")

ls.setup({
	ext_opts = {
		[types.insertNode] = {
			active = {...},
			visited = {...},
			passive = {...},
			snippet_passive = {...}
		},
		[types.choiceNode] = {
			active = {...},
			unvisited = {...}
		},
		[types.snippet] = {
			passive = {...}
		}
	}
})
```

The above applies the given `ext_opts` to all nodes of these types, in all
snippets...

```lua
local types = require("luasnip.util.types")

s("trig", { i(1, "text1"), i(2, "text2") }, {
	child_ext_opts = {
		[types.insertNode] = {
			passive = {
				hl_group = "GruvboxAqua"
			}
		}
	}
})
```
... while the `ext_opts` here are only applied to the `insertNodes` inside this
snippet.

---

By default, the `ext_opts` actually used for a node are created by extending the
`node_ext_opts` with the `effective_child_ext_opts[node.type]` of the parent,
which are in turn the parent's `child_ext_opts` extended with the global
`ext_opts` (those set `ls.setup`).

It's possible to prevent both of these merges by passing
`merge_node/child_ext_opts=false` to the snippet/node-opts:

```lua
ls.setup({
	ext_opts = {
		[types.insertNode] = {
			active = {...}
		}
	}
})

...

s("trig", {
	i(1, "text1", {
		node_ext_opts = {
			active = {...}
		},
		merge_node_ext_opts = false
	}),
	i(2, "text2")
}, {
	child_ext_opts = {
		[types.insertNode] = {
			passive = {...}
		}
	},
	merge_child_ext_opts = false
})
```

---

The `hl_group` of the global `ext_opts` can also be set via standard
highlight-groups:

```lua
vim.cmd("hi link LuasnipInsertNodePassive GruvboxRed")
vim.cmd("hi link LuasnipSnippetPassive GruvboxBlue")

-- needs to be called for resolving the effective ext_opts.
ls.setup({})
```
The names for the used highlight groups are
`"Luasnip<node>{Passive,Active,SnippetPassive}"`, where `<node>` can be any kind of
node in PascalCase (or "Snippet").

---

One problem that might arise when nested nodes are highlighted, is that the
highlight of inner nodes should be visible, eg. above that of nodes they are
nested inside.

This can be controlled using the `priority`-key in `ext_opts`. In
`nvim_buf_set_extmark`, that value is an absolute value, but here it is relative
to some base-priority, which is increased for each nesting level of
snippet(Nodes)s.

Both the initial base-priority and its' increase and can be controlled using
`ext_base_prio` and `ext_prio_increase`:
```lua
ls.setup({
	ext_opts = {
		[types.insertNode] = {
			active = {
				hl_group = "GruvboxBlue",
				-- the priorities should be \in [0, ext_prio_increase).
				priority = 1
			}
		},
		[types.choiceNode] = {
			active = {
				hl_group = "GruvboxRed"
				-- priority defaults to 0
			}
		}
	}
	ext_base_prio = 200,
	ext_prio_increase = 2
})
```
Here the highlight of an insertNode nested directly inside a choiceNode is
always visible on top of it.


# DOCSTRING

Snippet-docstrings can be queried using `snippet:get_docstring()`. The function
evaluates the snippet as if it was expanded regularly, which can be problematic
if e.g. a dynamicNode in the snippet relies on inputs other than
the argument-nodes.
`snip.env` and `snip.captures` are populated with the names of the queried
variable and the index of the capture respectively
(`snip.env.TM_SELECTED_TEXT` -> `'$TM_SELECTED_TEXT'`, `snip.captures[1]` ->
 `'$CAPTURES1'`). Although this leads to more expressive docstrings, it can
 cause errors in functions that e.g. rely on a capture being a number:

```lua
s({trig = "(%d)", regTrig = true}, {
	f(function(args, snip)
		return string.rep("repeatme ", tonumber(snip.captures[1]))
	end, {})
}),
```

This snippet works fine because	`snippet.captures[1]` is always a number.
During docstring-generation, however, `snippet.captures[1]` is `'$CAPTURES1'`,
which will cause an error in the functionNode.
Issues with `snippet.captures` can be prevented by specifying `docTrig` during
snippet-definition:

```lua
s({trig = "(%d)", regTrig = true, docTrig = "3"}, {
	f(function(args, snip)
		return string.rep("repeatme ", tonumber(snip.captures[1]))
	end, {})
}),
```

`snippet.captures` and `snippet.trigger` will be populated as if actually
triggered with `3`.

Other issues will have to be handled manually by checking the contents of e.g.
`snip.env` or predefining the docstring for the snippet:

```lua
s({trig = "(%d)", regTrig = true, docstring = "repeatmerepeatmerepeatme"}, {
	f(function(args, snip)
		return string.rep("repeatme ", tonumber(snip.captures[1]))
	end, {})
}),
```

A better example to understand `docTrig` and `docstring` can refer to
[#515](https://github.com/L3MON4D3/LuaSnip/pull/515).

# DOCSTRING-CACHE

Although generation of docstrings is pretty fast, it's preferable to not
redo it as long as the snippets haven't changed. Using
`ls.store_snippet_docstrings(snippets)` and its counterpart
`ls.load_snippet_docstrings(snippets)`, they may be serialized from or
deserialized into the snippets.
Both functions accept a table structsured like this: `{ft1={snippets},
ft2={snippets}}`. Such a table containing all snippets can be obtained via
`ls.get_snippets()`.
`load` should be called before any of the `loader`-functions as snippets loaded
from vscode-style packages already have their `docstring` set (`docstrings`
wouldn't be overwritten, but there'd be unnecessary calls).

The cache is located at `stdpath("cache")/luasnip/docstrings.json` (probably
`~/.cache/nvim/luasnip/docstrings.json`).

# EVENTS

Events can be used to react to some action inside snippets. These callbacks can
be defined per-snippet (`callbacks`-key in snippet constructor) or globally
(autocommand).

`callbacks`: `fn(node[, event_args]) -> event_res`  
All callbacks get the `node` associated with the event and event-specific
optional arguments, `event_args`.
`event_res` is only used in one event, `pre_expand`, where some properties of
the snippet can be changed.

`autocommand`:
Luasnip uses `User`-events. Autocommands for these can be registered using
```vim
au User SomeUserEvent echom "SomeUserEvent was triggered"
```

or
```lua
vim.api.nvim_create_autocommand("User", {
	patter = "SomeUserEvent",
	command = "echom SomeUserEvent was triggered"
})
```
The node and `event_args` can be accessed through `require("luasnip").session`:

* `node`: `session.event_node`  
* `event_args`: `session.event_args`

**Events**:

* `enter/leave`: Called when a node is entered/left (for example when jumping
  around in a snippet).  
  `User-event`: `"Luasnip<Node>{Enter,Leave}"`, with `<Node>` in
  PascalCase, e.g. `InsertNode` or `DynamicNode`.  
  `event_args`: none
* `change_choice`: When the active choice in a choiceNode is changed.  
  `User-event`: `"LuasnipChangeChoice"`  
  `event_args`: none
* `pre_expand`: Called before a snippet is expanded. Modifying text is allowed,
  the expand-position will be adjusted so the snippet expands at the same
  position relative to existing text.  
  `User-event`: `"LuasnipPreExpand"`  
  `event_args`:
  * `expand_pos`: `{<row>, <column>}`, position at which the snippet will be
  	expanded. `<row>` and `<column>` are both 0-indexed.
  `event_res`:
  * `env_override`: `map string->(string[]|string)`, override or extend the
    snippet's environment (`snip.env`).

A pretty useless, beyond serving as an example here, application of these would
be printing e.g. the nodes' text after entering:

```lua
vim.api.nvim_create_autocmd("User", {
	pattern = "LuasnipInsertNodeEnter",
	callback = function()
		local node = require("luasnip").session.event_node
		print(table.concat(node:get_text(), "\n"))
	end
})
```

or some information about expansions

```lua
vim.api.nvim_create_autocmd("User", {
	pattern = "LuasnipPreExpand",
	callback = function()
		-- get event-parameters from `session`.
		local snippet = require("luasnip").session.event_node
		local expand_position =
			require("luasnip").session.event_args.expand_pos

		print(string.format("expanding snippet %s at %s:%s",
			table.concat(snippet:get_docstring(), "\n"),
			expand_position[1],
			expand_position[2]
		))
	end
})
```

# CLEANUP
The function ls.cleanup()  triggers the `LuasnipCleanup` user-event, that you can listen to do some kind
of cleaning in your own snippets, by default it will  empty the snippets table and the caches of
the lazy_load.

# Logging
Luasnip uses logging to report unexpected program-states, and information on
what's going on in general. If something does not work as expected, taking a
look at the log (and potentially increasing the loglevel) might give some good
hints towards what is going wrong.  

The log is stored in `<vim.fn.stdpath("log")>/luasnip.log`
(`<vim.fn.stdpath("cache")>/luasnip.log` for neovim-versions where
`stdpath("log")` does not exist), and can be opened by calling `ls.log.open()`.
The loglevel (granularity of reported events) can be adjusted by calling
`ls.log.set_loglevel("error"|"warn"|"info"|"debug")`. `"debug"` has the highest
granularity, `"error"` the lowest, the default is `"warn"`.  

Once this log grows too large (10MiB, currently not adjustable), it will be
renamed to `luasnip.log.old`, and a new, empty log created in its place. If
there already exists a `luasnip.log.old`, it will be deleted.

`ls.log.ping()` can be used to verify the log is working correctly: it will
print a short message to the log.

# API-REFERENCE

`require("luasnip")`:

- `add_snippets(ft:string or nil, snippets:list or table, opts:table or nil)`:
  Makes `snippets` (list of snippets) available in `ft`.  
  If `ft` is `nil`, `snippets` should be a table containing lists of snippets,
  the keys are corresponding filetypes.  
  `opts` may contain the following keys:
  - `type`: type of `snippets`, `"snippets"` or `"autosnippets"` (ATTENTION:
	plural form used here). This serves as default value for the `snippetType`
	key of each snippet added by this call see [SNIPPETS](#SNIPPETS).

  - `key`: Key that identifies snippets added via this call.  
	If `add_snippets` is called with a key that was already used, the snippets
	from that previous call will be removed.  
	This can be used to reload snippets: pass an unique key to each
	`add_snippets` and just re-do the `add_snippets`-call when the snippets have
	changed.
  - `override_priority`: set priority for all snippets.
  - `default_priority`: set priority only for snippets without snippet-priority.

- `clean_invalidated(opts: table or nil) -> bool`: clean invalidated snippets
  from internal snippet storage.  
  Invalidated snippets are still stored, it might be useful to actually remove
  them, as they still have to be iterated during expansion.

  `opts` may contain:

  - `inv_limit`: how many invalidated snippets are allowed. If the number of
  	invalid snippets doesn't exceed this threshold, they are not yet cleaned up.

	A small number of invalidated snippets (<100) probably doesn't affect
	runtime at all, whereas recreating the internal snippet storage might.

- `get_id_snippet(id)`: returns snippet corresponding to id.

- `in_snippet()`: returns true if the cursor is inside the current snippet.

- `jumpable(direction)`: returns true if the current node has a
  next(`direction` = 1) or previous(`direction` = -1), e.g. whether it's
  possible to jump forward or backward to another node.

- `jump(direction)`: returns true if the jump was successful.

- `expandable()`: true if a snippet can be expanded at the current cursor position.

- `expand(opts)`: expands the snippet at(before) the cursor.
  `opts` may contain:
  - `jump_into_func` passed through to `ls.snip_expand`, check its' doc for a
  	description.

- `expand_or_jumpable()`: returns `expandable() or jumpable(1)` (exists only
  because commonly, one key is used to both jump forward and expand).

- `expand_or_locally_jumpable()`: same as `expand_or_jumpable()` except jumpable
  is ignored if the cursor is not inside the current snippet.

- `locally_jumpable(direction)`: same as `jumpable()` except it is ignored if the cursor
  is not inside the current snippet.

- `expand_or_jump()`: returns true if jump/expand was succesful.

- `expand_auto()`: expands the autosnippets before the cursor (not necessary
  to call manually, will be called via autocmd if `enable_autosnippets` is set
  in the config).

- `snip_expand(snip, opts)`: expand `snip` at the current cursor position.
  `opts` may contain the following keys:
    - `clear_region`: A region of text to clear after expanding (but before
      jumping into) snip. It has to be at this point (and therefore passed to
      this function) as clearing before expansion will populate `TM_CURRENT_LINE`
      and `TM_CURRENT_WORD` with wrong values (they would miss the snippet trigger)
      and clearing after expansion may move the text currently under the cursor
      and have it end up not at the `i(1)`, but a `#trigger` chars to it's right.
      The actual values used for clearing are `from` and `to`, both (0,0)-indexed
      byte-positions.
      If the variables don't have to be populated with the correct values, it's
      safe to remove the text manually.
    - `expand_params`: table, for overriding the `trigger` used in the snippet
      and setting the `captures` (useful for pattern-triggered nodes where the
      trigger has to be changed from the pattern to the actual text triggering the
      node).
      Pass as `trigger` and `captures`.
    - `pos`: position (`{line, col}`), (0,0)-indexed (in bytes, as returned by
      `nvim_win_get_cursor()`), where the snippet should be expanded. The
      snippet will be put between `(line,col-1)` and `(line,col)`. The snippet
      will be expanded at the current cursor if pos is nil.
    - `jump_into_func`: fn(snippet) -> node:
      Callback responsible for jumping into the snippet. The returned node is
      set as the new active node, ie. it is the origin of the next jump.
      The default is basically this
      ```lua
      function(snip)
      	-- jump_into set the placeholder of the snippet, 1
      	-- to jump forwards.
      	return snip:jump_into(1)
      ```
      While this can be used to only insert the snippet
      ```lua
      function(snip)
      	return snip.insert_nodes[0]
      end
      ```

  `opts` and any of its parameters may be nil.

- `get_active_snip()`: returns the currently active snippet (not node!).

- `choice_active()`: true if inside a choiceNode.

- `change_choice(direction)`: changes the choice in the innermost currently
  active choiceNode forward (`direction` = 1) or backward (`direction` = -1).

- `unlink_current()`: removes the current snippet from the jumplist (useful
  if luasnip fails to automatically detect e.g. deletion of a snippet) and
  sets the current node behind the snippet, or, if not possible, before it.

- `lsp_expand(snip_string, opts)`: expand the lsp-syntax-snippet defined via
  `snip_string` at the cursor.
  `opts` can have the same options as `opts` in `snip_expand`.

- `active_update_dependents()`: update all function/dynamicNodes that have the
  current node as an argnode (will actually only update them if the text in any
  of the argnodes changed).

- `available(snip_info)`: return a table of all snippets defined for the
  current filetypes(s) (`{ft1={snip1, snip2}, ft2={snip3, snip4}}`).
  The structure of the snippet is defined by `snip_info` which is a function
  (`snip_info(snip)`) that takes in a snippet (`snip`), finds the desired
  information on it, and returns it.
  `snip_info` is an optional argument as a default has already been defined.
  You can use it for more granular control over the table of snippets that is
  returned.

- `exit_out_of_region(node)`: checks whether the cursor is still within the
  range of the snippet `node` belongs to. If yes, no change occurs, if No, the
  snippet is exited and following snippets' regions are checked and potentially
  exited (the next active node will be the 0-node of the snippet before the one
  the cursor is inside.
  If the cursor isn't inside any snippet, the active node will be the last node
  in the jumplist).
  If a jump causes an error (happens mostly because a snippet was deleted), the
  snippet is removed from the jumplist.

- `store_snippet_docstrings(snippet_table)`: Stores the docstrings of all
  snippets in `snippet_table` to a file
  (`stdpath("cache")/luasnip/docstrings.json`).
  Calling `store_snippet_docstrings(snippet_table)` after adding/modifying
  snippets and `load_snippet_docstrings(snippet_table)` on startup after all
  snippets have been added to `snippet_table` is a way to avoide regenerating
  the (unchanged) docstrings on each startup.
  (Depending on when the docstrings are required and how luasnip is loaded,
  it may be more sensible to let them load lazily, e.g. just before they are
  required).
  `snippet_table` should be laid out just like `luasnip.snippets` (it will
  most likely always _be_ `luasnip.snippets`).

- `load_snippet_docstrings(snippet_table)`: Load docstrings for all snippets
  in `snippet_table` from `stdpath("cache")/luasnip/docstrings.json`.
  The docstrings are stored and restored via trigger, meaning if two
  snippets for one filetype have the same(very unlikely to happen in actual
  usage), bugs could occur.
  `snippet_table` should be laid out as described in `store_snippet_docstrings`.

- `unlink_current_if_deleted()`: Checks if the current snippet was deleted,
  if so, it is removed from the jumplist. This is not 100% reliable as
  luasnip only sees the extmarks and their beginning/end may not be on the same
  position, even if all the text between them was deleted.

- `filetype_extend(filetype:string, extend_filetypes:table of string)`: Tells
  luasnip that for a buffer with `ft=filetype`, snippets from
  `extend_filetypes` should be searched as well. `extend_filetypes` is a
  lua-array (`{ft1, ft2, ft3}`).
  `luasnip.filetype_extend("lua", {"c", "cpp"})` would search and expand c-and
  cpp-snippets for lua-files.

- `filetype_set(filetype:string, replace_filetypes:table of string)`: Similar
  to `filetype_extend`, but where _append_ appended filetypes, _set_ sets them:
  `filetype_set("lua", {"c"})` causes only c-snippets to be expanded in
  lua-files, lua-snippets aren't even searched.

- `cleanup()`: clears all snippets. Not useful for regular usage, only when
  authoring and testing snippets.

- `refresh_notify(ft:string)`: Triggers an autocmd that other plugins can hook
  into to perform various cleanup for the refreshed filetype.
  Useful for signaling that new snippets were added for the filetype `ft`.

- `set_choice(indx:number)`: Changes to the `indx`th choice.
  If no `choiceNode` is active, an error is thrown.
  If the active `choiceNode` doesn't have an `indx`th choice, an error is
  thrown.

- `get_current_choices() -> string[]`: Returns a list of multiline-strings
  (themselves lists, even if they have only one line), the `i`th string
  corresponding to the `i`th choice of the currently active `choiceNode`.
  If no `choiceNode` is active, an error is thrown.

- `setup_snip_env()`: Adds the variables defined (during `setup`) in `snip_env`
  to the callers environment.

- `get_snip_env()`: Returns `snip_env`.

Not covered in this section are the various node-constructors exposed by
the module, their usage is shown either previously in this file or in
`Examples/snippets.lua` (in the repo).
