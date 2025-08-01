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

LuaSnip is a snippet engine written entirely in Lua. It has some great
features like inserting text (`luasnip-function-node`) or nodes
(`luasnip-dynamic-node`) based on user input, parsing LSP syntax and switching
nodes (`luasnip-choice-node`).
For basic setup like mappings and installing, check the README.

All code snippets in this help assume the following:

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
local ms = ls.multi_snippet
local k = require("luasnip.nodes.key_indexer").new_key
```

As noted in the [Loaders-Lua](#lua)-section:

> By default, the names from [`luasnip.config.snip_env`][snip-env-src] will be used, but it's possible to customize them by setting `snip_env` in `setup`. 

Furthermore, note that while this document assumes you have defined `ls` to be `require("luasnip")`, it is **not** provided in the default set of variables.

<!-- panvimdoc-ignore-start -->

Note: the source code of snippets in GIFs is actually
[here](https://github.com/zjp-CN/neovim0.6-blogs/commit/2bff84ef53f8da5db9dcf2c3d97edb11b2bf68cd),
and it's slightly different from the code below.

<!-- panvimdoc-ignore-end -->

# Basics
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
It is explained in more detail in [Snippets](#snippets), but the gist is that
it creates a snippet that contains the nodes specified in `nodes`, which will be
inserted into a buffer if the text before the cursor matches `trigger` when
`ls.expand` is called.  

## Jump-Index
Nodes that can be jumped to (`insertNode`, `choiceNode`, `dynamicNode`,
`restoreNode`, `snippetNode`) all require a "jump-index" so LuaSnip knows the
order in which these nodes are supposed to be visited ("jumped to").  

```lua
s("trig", {
	i(1), t"text", i(2), t"text again", i(3)
})
```

These indices don't "run" through the entire snippet, like they do in
TextMate-snippets (`"$1 ${2: $3 $4}"`), they restart at 1 in each nested
snippetNode:
```lua
s("trig", {
	i(1), t" ", sn(2, {
		t" ", i(1), t" ", i(2)
	})
})
```
(roughly equivalent to the given TextMate-snippet).

## Adding Snippets
The snippets for a given filetype have to be added to LuaSnip via
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
`ls.filetype_extend`, more info on that in the section [API](#api-2).

## Snippet Insertion
When a new snippet is expanded, it can be connected with the snippets that have
already been expanded in the buffer in various ways.  
First of all, Luasnip distinguishes between root-snippets and child-snippets.
The latter are nested inside other snippets, so when jumping through a snippet,
one may also traverse the child-snippets expanded inside it, more or less as if
the child just contains more nodes of the parent.  
Root-snippets are of course characterized by not being child-snippets.  
When expanding a new snippet, it becomes a child of the snippet whose region it
is expanded inside, and a root if it is not inside any snippet's region.  
If it is inside another snippet, the specific node it is inside is determined,
and the snippet then nested inside that node.

* If that node is interactive (for example, an `insertNode`), the new snippet
  will be traversed when the node is visited, as long as the
  configuration-option `link_children` is enabled. If it is not enabled, it is
  possible to jump from the snippet to the node, but not the other way around.
* If that node is not interactive, the snippet will be linked to the currently
  active node, also such that it will not be jumped to again once it is left.
  This is to prevent jumping large distances across the buffer as much as
  possible. There may still be one large jump from the snippet back to the
  current node it is nested inside, but that seems hard to avoid.  
  Thus, one should design snippets such that the regions where other snippets
  may be expanded are inside `insertNodes`.

If the snippet is not a child, but a root, it can be linked up with the roots
immediately adjacent to it by enabling `link_roots` in `setup`.
Since by default only one root is remembered, one should also set `keep_roots`
if `link_roots` is enabled. The two are separate options, since roots that are
not linked can still be reached by `ls.activate_node()`. This setup (remember
roots, but don't jump to them) is useful for a super-tab like mapping (`<Tab>`
and jump on the same key), where one would like to still enter previous roots.
Since there would almost always be more jumps if the roots are linked, regular
`<Tab>` would not work almost all the time, and thus `link_roots` has to stay
disabled.

# Node

Every node accepts, as its last parameter, an optional table of arguments.
There are some common ones (which are listed here), and some that only apply to
some nodes (`user_args` for function/dynamicNode). These `opts` are
only mentioned if they accept options that are not common to all nodes.

Common opts:

* `node_ext_opts` and `merge_node_ext_opts`: Control `ext_opts` (most likely
  highlighting) of the node. Described in detail in [ext_opts](#ext_opts)
* `key`: The node can be referred to by this key. Useful for either
  [Key Indexer](#key-indexer) or for finding the node at runtime (See
  [Snippets-API](#snippets-api)), for example inside a `dynamicNode`. The keys
  do not have to be unique across the entire lifetime of the snippet, but at any
  point in time, the snippet may contain each key only once. This means it is
  fine to return a keyed node from a `dynamicNode`, because even if it will be
  generated multiple times, those will not be valid at the same time.
* `node_callbacks`: Define event-callbacks for this node (see
  [events](#events)).  
  Accepts a table that maps an event, e.g. `events.enter` to the callback
  (essentially the same as `callbacks` passed to `s`, only that there is no
  first mapping from jump-index to the table of callbacks).

## API

- `get_jump_index()`: this method returns the jump-index of a node. If a node 
  doesn't have a jump-index, this method returns `nil` instead.
- `get_buf_position(opts) -> {from_position, to_position}`:
  Determines the range of the buffer occupied by this node. `from`- and
  `to_position` are `row,column`-tuples, `0,0`-indexed (first line is 0, first
  column is 0) and end-inclusive (see `:h api-indexing`, this is extmarks
  indexing).
  - `opts`: `table|nil`, options, valid keys are:
    - `raw`: `bool`, default `true`. This can be used to switch between
	  byte-columns (`raw=true`) and visual columns (`raw=false`). This makes a
	  difference if the line contains characters represented by multiple bytes
	  in UTF, for example `ÿ`.

# Snippets

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
  - `trig`: string, the trigger of the snippet. If the text in front of (to the
    left of) the cursor when `ls.expand()` is called matches it, the snippet
    will be expanded.  
    By default, "matches" means the text in front of the cursor matches the
    trigger exactly, this behavior can be modified through `trigEngine`
  - `name`: string, can be used by e.g. `nvim-compe` to identify the snippet.
  - `desc` (or `dscr`): string, description of the snippet, \n-separated or table
    for multiple lines.
  - `wordTrig`: boolean, if true, the snippet is only expanded if the word
    (`[%w_]+`) before the cursor matches the trigger entirely.
    True by default.
  - `regTrig`: boolean, whether the trigger should be interpreted as a
    Lua pattern. False by default.  
    Consider setting `trigEngine` to `"pattern"` instead, it is more expressive,
    and in line with other settings.
  - `trigEngine`: (function|string), determines how `trig` is interpreted, and
    what it means for it to "match" the text in front of the cursor.  
    This behavior can be completely customized by passing a function, but the
    predefined ones, which are accessible by passing their identifier, should
    suffice in most cases:
    * `"plain"`: the default-behavior, the trigger has to match the text before
      the cursor exactly.
    * `"pattern"`: the trigger is interpreted as a Lua pattern, and is a match if
      `trig .. "$"` matches the line up to the cursor. Capture-groups will be
      accessible as `snippet.captures`.
    * `"ecma"`: the trigger is interpreted as an ECMAscript-regex, and is a
      match if `trig .. "$"` matches the line up to the cursor. Capture-groups
      will be accessible as `snippet.captures`.  
      This `trigEngine` requires `jsregexp` (see
      [LSP-snippets-transformations](#transformations)) to be installed, if it
      is not, this engine will behave like `"plain"`.
    * `"vim"`: the trigger is interpreted as a vim-regex, and is a match if
      `trig .. "$"` matches the line up to the cursor. As with the other
      regex/pattern-engines, captures will be available as `snippet.captures`,
      but there is one caveat: the matching is done using `matchlist`, so for
      now empty-string submatches will be interpreted as unmatched, and the
      corresponding `snippet.capture[i]` will be `nil` (this will most likely
      change, don't rely on this behavior).

    Besides these predefined engines, it is also possible to create new ones:
    Instead of a string, pass a function which satisfies
    `trigEngine(trigger, opts) -> (matcher(line_to_cursor, trigger) ->
    whole_match, captures)`
    (i.e. the function receives `trig` and `trigEngineOpts` can, for example,
    precompile a regex, and then returns a function responsible for determining
    whether the current cursor-position (represented by the line up to the
    cursor) matches the trigger (it is passed again here so engines which don't
    do any trigger-specific work (like compilation) can just return a static
    `matcher`), and what the capture-groups are).  
    The `lua`-engine, for example, can be implemented like this:
    ```lua
    local function matcher(line_to_cursor, trigger)
        -- look for match which ends at the cursor.
        -- put all results into a list, there might be many capture-groups.
        local find_res = { line_to_cursor:find(trigger .. "$") }

        if #find_res > 0 then
            -- if there is a match, determine matching string, and the
            -- capture-groups.
            local captures = {}
            -- find_res[1] is `from`, find_res[2] is `to` (which we already know
            -- anyway).
            local from = find_res[1]
            local match = line_to_cursor:sub(from, #line_to_cursor)
            -- collect capture-groups.
            for i = 3, #find_res do
                captures[i - 2] = find_res[i]
            end
            return match, captures
        else
            return nil
        end
    end

    local function engine(trigger)
        -- don't do any special work here, can't precompile lua-pattern.
        return matcher
    end
    ```
    The predefined engines are defined in
    [`trig_engines.lua`](https://github.com/L3MON4D3/LuaSnip/blob/master/lua/luasnip/nodes/util/trig_engines.lua),
    read it for more examples.

  - `trigEngineOpts`: `table<string, any>`, options for the used `trigEngine`.  
    The valid options are:
    * `max_len`: number, upper bound on the length of the trigger.  
      If this is set, the `line_to_cursor` will be truncated (from the cursor of
      course) to `max_len` characters before performing the match.  
      This is implemented because feeding long `line_to_cursor` into e.g. the
      pattern-`trigEngine` will hurt performance quite a bit (see issue
      Luasnip#1103).  
      This option is implemented for all `trigEngines`. 

  - `docstring`: string, textual representation of the snippet, specified like
    `desc`. Overrides docstrings loaded from `json`.
  - `docTrig`: string, used as `line_to_cursor` during docstring-generation.
    This might be relevant if the snippet relies on specific values in the
    capture-groups (for example, numbers, which won't work with the default
    `$CAPTURESN` used during docstring-generation)
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
  - `resolveExpandParams`: `fn(snippet, line_to_cursor, matched_trigger, captures) -> table|nil`, where
    - `snippet`: `Snippet`, the expanding snippet object
    - `line_to_cursor`: `string`, the line up to the cursor.
    - `matched_trigger`: `string`, the fully matched trigger (can be retrieved
    	from `line_to_cursor`, but we already have that info here :D)
    - `captures`: `captures` as returned by `trigEngine`.

    This function will be evaluated in `Snippet:matches()` to decide whether
    the snippet can be expanded or not.  
    Returns a table if the snippet can be expanded, `nil` if can not. The
    returned table can contain any of these fields:
      - `trigger`: `string`, the fully matched trigger.
      - `captures`: `table`, this list could update the capture-groups from
        parameter in snippet expansion.
        Both `trigger` and `captures` can override the values returned via
        `trigEngine`.  
      - `clear_region`: `{ "from": {<row>, <column>}, "to": {<row>, <column>} }`,
        both (0, 0)-indexed, the region where text has to be cleared before
        inserting the snippet.
      - `env_override`: `map string->(string[]|string)`, override or extend
        the snippet's environment (`snip.env`)

      If any of these is `nil`, the default is used (`trigger` and `captures` as
      returned by `trigEngine`, `clear_region` such that exactly the trigger is
      deleted, no overridden environment-variables).

      A good example for the usage of `resolveExpandParams` can be found in
      the implementation of
      [`postfix`](https://github.com/L3MON4D3/LuaSnip/blob/master/lua/luasnip/extras/postfix.lua).
  - `condition`: `fn(line_to_cursor, matched_trigger, captures) -> bool`, where
      - `line_to_cursor`: `string`, the line up to the cursor.
      - `matched_trigger`: `string`, the fully matched trigger (can be retrieved
      	from `line_to_cursor`, but we already have that info here :D)
      - `captures`: if the trigger is pattern, this list contains the
      	capture-groups. Again, could be computed from `line_to_cursor`, but we
      	already did so.

      This function can prevent manual snippet expansion via `ls.expand()`.  
      Return `true` to allow expansion, and `false` to prevent it.
  - `show_condition`: `f(line_to_cursor) -> bool`.  
    - `line_to_cursor`: `string`, the line up to the cursor.  

	This function is (should be) evaluated by completion engines, indicating
	whether the snippet should be included in current completion candidates.  
    Defaults to a function returning `true`.  
    This is different from `condition` because `condition` is evaluated by
    LuaSnip on snippet expansion (and thus has access to the matched trigger and
	captures), while `show_condition` is (should be) evaluated by the
	completion engines when scanning for available snippet candidates.
  - `filetype`: `string`, the filetype of the snippet.
    This overrides the filetype the snippet is added (via `add_snippet`) as.

- `nodes`: A single node or a list of nodes. The nodes that make up the
  snippet.

- `opts`: A table with the following valid keys:
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
    More info on events in [events](#events)
  - `child_ext_opts`, `merge_child_ext_opts`: Control `ext_opts` applied to the
    children of this snippet. More info on those in the
    [ext_opts](#ext_opts)-section.

The `opts`-table, as described here, can also be passed to e.g. `snippetNode`
and `indentSnippetNode`.  
It is also possible to set `condition` and `show_condition` (described in the
documentation of the `context`-table) from `opts`. They should, however, not be
set from both.

## Data

Snippets contain some interesting tables during runtime:

- `snippet.env`: Contains variables used in the LSP-protocol, for example
  `TM_CURRENT_LINE` or `TM_FILENAME`. It's possible to add customized variables
  here too, check [Variables-Environment Namespaces](#environment-namespaces)
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

<a id="snippets-api"></a>
## API

- `invalidate()`: call this method to effectively remove the snippet. The
  snippet will no longer be able to expand via `expand` or `expand_auto`. It
  will also be hidden from lists (at least if the plugin creating the list
  respects the `hidden`-key), but it might be necessary to call
  `ls.refresh_notify(ft)` after invalidating snippets.
- `get_keyed_node(key)`: Returns the currently visible node associated with
  `key`.


# TextNode

The most simple kind of node; just text.
```lua
s("trigger", { t("Wow! Text!") })
```
This snippet expands to

```
    Wow! Text!⎵
```
where ⎵ is the cursor.

Multiline strings can be defined by passing a table of lines rather than a
string:

```lua
s("trigger", {
	t({"Wow! Text!", "And another line."})
})
```

`t(text, node_opts)`:

- `text`: `string` or `string[]`
- `node_opts`: `table`, see [Node](#node)

# InsertNode

These Nodes contain editable text and can be jumped to- and from (e.g.
traditional placeholders and tabstops, like `$1` in TextMate-snippets).

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

The Insert Nodes are visited in order `1,2,3,..,n,0`.  
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

An **important** (because here Luasnip differs from other snippet engines) detail
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

as opposed to e.g. the TextMate syntax, where tabstops are snippet-global:
```snippet
${1:First jump} :: ${2: ${3:Third jump} : ${4:Fourth jump}}
```
(this is not exactly the same snippet of course, but as close as possible)
(the restart-rule only applies when defining snippets in Lua, the above
TextMate-snippet will expand correctly when parsed).

`i(jump_index, text, node_opts)`

- `jump_index`: `number`, this determines when this node will be jumped to (see
  [Basics-Jump-Index](#jump-index)).
- `text`: `string|string[]`, a single string for just one line, a list with >1
  entries for multiple lines.
  This text will be `SELECT`ed when the `insertNode` is jumped into.
- `node_opts`: `table`, described in [Node](#node)

If the `jump_index` is `0`, replacing its' `text` will leave it outside the
`insertNode` (for reasons, check out Luasnip#110).


# FunctionNode

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
    (e.g. `{{line1}, {line1, line2}}`). The snippet indent will be removed from
    all lines following the first.

  - `parent`: The immediate parent of the `functionNode`.  
    It is included here as it allows easy access to some information that could
    be useful in functionNodes (see [Snippets-Data](#data) for some examples).  
    Many snippets access the surrounding snippet just as `parent`, but if the
    `functionNode` is nested within a `snippetNode`, the immediate parent is a
    `snippetNode`, not the surrounding snippet (only the surrounding snippet
    contains data like `env` or `captures`).

  - `user_args`: The `user_args` passed in `opts`. Note that there may be multiple `user_args`
    (e.g. `user_args1, ..., user_argsn`).
  
  `fn` shall return a string, which will be inserted as is, or a table of
  strings for multiline strings, where all lines following the first will be
  prefixed with the snippets' indentation.

- `argnode_references`: `node_reference[]|node_refernce|nil`.  
  Either no, a single, or multiple [Node Reference](#node-reference)s.
  Changing any of these will trigger a re-evaluation of `fn`, and insertion of
  the updated text.  
  If no node reference is passed, the `functionNode` is evaluated once upon
  expansion.

- `node_opts`: `table`, see [Node](#node). One additional key is supported:
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

- Use captures from the regex trigger using a functionNode:

  ```lua
  s({trig = "b(%d)", regTrig = true},
  	f(function(args, snip) return
  		"Captured Text: " .. snip.captures[1] .. "." end, {})
  )
  ```
  
  <!-- panvimdoc-ignore-start -->
  
  ![FunctionNode3](https://user-images.githubusercontent.com/25300418/184359248-6b13a80c-f644-4979-a566-958c65a4e047.gif)
  
  <!-- panvimdoc-ignore-end -->

- `argnodes_text` during function evaluation:

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

- [Absolute Indexer](#absolute-indexer):

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
the `lambda` from `luasnip.extras` (See [Extras-Lambda](#lambda))

# Node Reference
Node references are used to refer to other nodes in various parts of LuaSnip's
API.  
For example, argnodes in functionNode, dynamicNode or lambda are
node references.  
These references can be either of:

  - `number`: the jump-index of the node.
    This will be resolved relative to the parent of the node this is passed to.
    (So, only nodes with the same parent can be referenced. This is very easy to
    grasp, but also limiting)
  - `key_indexer`: the key of the node, if it is present. This will come in
    handy if the node that is being referred to is not in the same
    snippet/snippetNode as the one the node reference is passed to.
    Also, it is the proper way to refer to a non-interactive node (a
    functionNode, for example)
  - `absolute_indexer`: the absolute position of the node. Just like
    `key_indexer`, it allows addressing non-sibling nodes, but is a bit more
    awkward to handle since a path from root to node has to be determined,
    whereas `key_indexer` just needs the key to match.  
    Due to this, `key_indexer` should be generally preferred.
    (More information in [Absolute Indexer](#absolute-indexer)).
  - `node`: just the node. Usage of this is discouraged since it can lead to
    subtle errors (for example, if the node passed here is captured in a closure
    and therefore not copied with the remaining tables in the snippet; there's a
    big comment about just this in commit `8bfbd61`).

# ChoiceNode

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

`c(pos, choices, opts?): LuaSnip.ChoiceNode`: Create a new choiceNode from a list of choices. The
first item in this list is the initial choice, and it can be changed while any node of a choice is
active. So, if all choices should be reachable, every choice has to have a place for the cursor to
stop at.

If the choice is a snippetNode like `sn(nil, {...nodes...})` the given `nodes` have to contain an
`insertNode` (e.g. `i(1)`). Using an `insertNode` or `textNode` directly as a choice is also fine,
the latter is special-cased to have a jump-point at the beginning of its text.

* `pos: integer` Jump-index of the node. (See [Basics-Jump-Index](#jump-index))
* `choices: (LuaSnip.Node|LuaSnip.Node[])[]` A list of nodes that can be switched between
  interactively. If a list of nodes is passed as a choice, it will be turned into a snippetNode.
  Jumpable nodes that generally need a jump-index don't need one when used as a choice since they
  inherit the choiceNode's jump-index anyway.
* `opts?: LuaSnip.Opts.ChoiceNode?` Additional optional arguments.  
  Valid keys are:

  * `restore_cursor?: boolean?` If set, the currently active node is looked up in the switched-to
    choice, and the cursor restored to preserve the current position relative to that node. The node
    may be found if a `restoreNode` is present in both choice. Defaults to `false`, as enabling
    might lead to decreased performance.

    It's possible to override the default by wrapping the `choiceNode` constructor in another
    function that sets `opts.restore_cursor` to `true` and then using that to construct
    `choiceNode`s:
    ```lua
    local function restore_cursor_choice(pos, choices, opts)
        opts = opts or {}
        opts.restore_cursor = true
        return c(pos, choices, opts)
    end
    ```
    Consider passing this override into `snip_env`.
  * `node_callbacks?: { [("change_choice"|"enter"...)]: fun(...) -> ... }?`
  * `node_ext_opts?: LuaSnip.NodeExtOpts?` Pass these opts through to the underlying extmarks
    representing the node. Notably, this enables highlighting the nodes, and allows the highlight to
    be different based on the state of the node/snippet. See [ext_opts](#ext_opts)
  * `merge_node_ext_opts?: boolean?` Whether to use the parents' `ext_opts` to compute this nodes'
    `ext_opts`.
  * `key: any` Some unique value (strings seem useful) to identify this node. This is useful for
    [Key Indexer](#key-indexer) or for finding the node at runtime (See
    [Snippets-API](#snippets-api) These keys don't have to be unique across the entire lifetime of
    the snippet, but every key should occur only once at the same time. This means it is fine to
    return a keyed node from a dynamicNode, because even if it will be generated multiple times, the
    same key not occur twice at the same time.

**Examples:**
```lua
c(1, {
	t"some text", -- textNodes are just stopped at.
	i(nil, "some text"), -- likewise.
	sn(nil, {t"some text"}) -- this will not work!
	sn(nil, {i(1), t"some text"}) -- this will.
})
```

The active choice for a `choiceNode` can be changed by either calling one of
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

Apart from this, there is also a picker (see [select_choice](#select_choice)
where no cycling is necessary and any choice can be selected right away, via
`vim.ui.select`.

# SnippetNode

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

- `jump_index`: `number`, the usual [Jump-Index](#jump-index).
- `nodes`: `node[]|node`, just like for `s`.  
  Note that `snippetNode`s don't accept an `i(0)`, so the jump-indices of the nodes
  inside them have to be in `1,2,...,n`.
- `node_opts`: `table`: again, the keys common to all nodes (documented in
  [Node](#node)) are supported, but also
  - `callbacks`,
  - `child_ext_opts` and
  - `merge_child_ext_opts`,

  which are further explained in [Snippets](#snippets).

# IndentSnippetNode

By default, all nodes are indented at least as deep as the trigger. With these
nodes it's possible to override that behavior:

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

(Note the empty string passed to `isn`).

Indent is only applied after line breaks, so it's not possible to remove indent
on the line where the snippet was triggered using `ISN` (That is possible via
regex triggers where the entire line before the trigger is matched).

Another nice use case for `ISN` is inserting text, e.g. `//` or some other comment
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
applied after line breaks.

To enable such usage, `$PARENT_INDENT` in the `indentstring` is replaced by the
parent's indent.

`isn(jump_index, nodes, indentstring, node_opts)`

All of these parameters except `indentstring` are exactly the same as in
[SnippetNode](#snippetnode).

- `indentstring`: `string`, will be used to indent the nodes inside this
  `snippetNode`.  
  All occurrences of `"$PARENT_INDENT"` are replaced with the actual indent of
  the parent.

# DynamicNode

Very similar to functionNode, but returns a snippetNode instead of just text,
which makes them very powerful as parts of the snippet can be changed based on
user input.

`d(jump_index, function, node-references, opts)`:

- `jump_index`: `number`, just like all jumpable nodes, its' position in the
   jump-list ([Basics-Jump-Index](#jump-index)).
- `function`: `fn(args, parent, old_state, user_args) -> snippetNode`
   This function is called when the argnodes' text changes. It should generate
   and return (wrapped inside a `snippetNode`) nodes, which will be inserted at
   the dynamicNode's place.  
   `args`, `parent` and `user_args` are also explained in
   [FunctionNode](#functionnode)
   - `args`: `table of text` (`{{"node1line1", "node1line2"}, {"node2line1"}}`)
     from nodes the `dynamicNode` depends on.
   - `parent`: the immediate parent of the `dynamicNode`.
   - `old_state`: a user-defined table. This table may contain anything; its
   	 intended usage is to preserve information from the previously generated
   	 `snippetNode`. If the `dynamicNode` depends on other nodes, it may be
   	 reconstructed, which means all user input (text inserted in `insertNodes`,
   	 changed choices) to the previous `dynamicNode` is lost.  
     The `old_state` table must be stored in `snippetNode` returned by
     the function (`snippetNode.old_state`).  
     The second example below illustrates the usage of `old_state`.
   - `user_args`: passed through from `dynamicNode`-opts; may have more than one
   	 argument.
- `node_references`: `node_reference[]|node_references|nil`,
  [Node References](#node-reference) to the nodes the dynamicNode depends on: if any
  of these trigger an update (for example, if the text inside them
  changes), the `dynamicNode`s' function will be executed, and the result
  inserted at the `dynamicNode`s place.  
  (`dynamicNode` behaves exactly the same as `functionNode` in this regard).

- `opts`: In addition to the common [Node](#node)-keys, there is, again, 
  - `user_args`, which is described in [FunctionNode](#functionnode).

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

# RestoreNode

This node can store and restore a snippetNode as is. This includes changed
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

- `jump_index`, when to jump to this node.
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
})
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
})
```
Now the entered text is stored.

`restoreNode`s indent is not influenced by `indentSnippetNodes` right now. If
that really bothers you feel free to open an issue.

<!-- panvimdoc-ignore-start -->

![RestoreNode3](https://user-images.githubusercontent.com/25300418/184359340-35c24160-10b0-4f72-849e-1015f59ed599.gif)

<!-- panvimdoc-ignore-end -->

# Key Indexer

A very flexible way of referencing nodes ([Node Reference](#node-reference)).  
While the straightforward way of addressing nodes via their
[Jump-Index](#jump-index) suffices in most cases, a `dynamic/functionNode` can
only depend on nodes in the same snippet(Node), its siblings (since the index is
interpreted as relative to their parent). Accessing a node with a different
parent is thus not possible. Secondly, and less relevant, only nodes that
actually have a jump-index can be referred to (a `functionNode`, for example,
cannot be depended on).  
Both of these restrictions are lifted with `key_indexer`:  
It allows addressing nodes by their key, which can be set when the node is
constructed, and is wholly independent of the nodes' position in the snippet,
thus enabling descriptive labeling.

The following snippets demonstrate the issue and the solution by using
`key_indexer`:

First, the addressed problem of referring to nodes outside the `functionNode`s
parent:
```lua
s("trig", {
	i(1), c(2, {
		sn(nil, {
			t"cannot access the argnode :(",
			f(function(args)
			    return args[1]
            end, {???}) -- can't refer to i(1), since it isn't a sibling of `f`.
		}),
		t"sample_text"
	})
})
```

And the solution: first give the node we want to refer to a key, and then pass
the same to the `functionNode`.
```lua
s("trig", {
	i(1, "", {key = "i1-key"}), c(2, {
		sn(nil, { i(1),
			t"can access the argnode :)",
			f(function(args)
                return args[1]
            end, k("i1-key") )
		}),
		t"sample_text"
	})
})
```

<!-- panvimdoc-ignore-start -->

![Key/AbsoluteIndexer](https://user-images.githubusercontent.com/25300418/184359369-3bbd2b30-33d1-4a5d-9474-19367867feff.gif)

<!-- panvimdoc-ignore-end -->


# Absolute Indexer

`absolute_indexer` allows accessing nodes by their unique jump-index path from
the snippet-root. This makes it almost as powerful as [Key Indexer](#key-indexer),
but again removes the possibility of referring to non-jumpable nodes and makes
it all a bit more error-prone since the jump-index paths are hard to follow, and
(unfortunately) have to be a bit verbose (see the long example of
`absolute_indexer`-positions below). Consider just using [Key Indexer](#key-indexer)
instead.  

(The solution-snippet from [Key Indexer](#key-indexer), but using `ai` instead.)
```lua
s("trig", {
	i(1), c(2, {
		sn(nil, { i(1),
			t"can access the argnode :)",
			f(function(args)
                return args[1]
            end, ai(1) )
		}),
		t"sample_text"
	})
})
```

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
	end, {}),
	r(5, "restore_key", -- ai[5]
		i(1) -- ai[5][0][1]: restoreNodes always store snippetNodes.
	),
	r(6, "restore_key_2", -- ai[6]
		sn(nil, { -- ai[6][0]
			i(1) -- ai[6][0][1]
		})
	)
})
```

Note specifically that the index of a dynamicNode differs from that of the
generated snippetNode, and that restoreNodes (internally) always store a
snippetNode, so even if the restoreNode only contains one node, that node has
to be accessed as `ai[restoreNodeIndx][0][1]`.

`absolute_indexer`s' can be constructed in different ways:

* `ai[1][2][3]`
* `ai(1, 2, 3)`
* `ai{1, 2, 3}`

are all the same node.

# MultiSnippet

There are situations where it might be comfortable to access a snippet in
different ways. For example, one might want to enable auto-triggering in regions
where the snippets usage is common, while leaving it manual-only in others.  
This is where `ms` should be used: A single snippet can be associated with multiple
`context`s (the `context`-table determines the conditions under which a snippet
may be triggered).  
This has the advantage (compared with just registering copies) that all
`context`s are backed by a single snippet, and not multiple, and it's (at least
should be :D) more comfortable to use.

`ms(contexts, nodes, opts) -> addable`:

- `contexts`: table containing list of `contexts`, and some keywords.  
  `context` are described in [Snippets](#snippets), here they may also be tables
  or strings.  
  So far, there is only one valid keyword:
  - `common`: Accepts yet another context.  
    The options in `common` are applied to (but don't override) the other
    contexts specified in `contexts`.
- `nodes`: List of nodes, exactly like in [Snippets](#snippets).
- `opts`: Table, options for this function:
  - `common_opts`: The snippet-options (see also [Snippets](#snippets)) applied
    to the snippet generated from `nodes`.

The returned object is an `addable`, something which can be passed to
`add_snippets`, or returned from the `lua-loader`.

**Examples**:
```lua
ls.add_snippets("all", {
    ms({"a", "b"}, {t"a or b"})
})
```

```lua
ls.add_snippets("all", {
    ms({
        common = {snippetType = "autosnippet"},
        "a",
        "b"
    }, {
        t"a or b (but autotriggered!!)"
    })
})
```

```lua
ls.add_snippets("all", {
    ms({
        common = {snippetType = "autosnippet"},
        {trig = "a", snippetType = "snippet"},
        "b",
        {trig = "c", condition = function(line_to_cursor)
            return line_to_cursor == ""
        end}
    }, {
        t"a or b (but autotriggered!!)"
    })
})
```

# Extras

## Lambda
A shortcut for `functionNode`s that only do very basic string
manipulation.

`l(lambda, argnodes)`:

- `lambda`: An object created by applying string-operations to `l._n`, objects
  representing the `n`th argnode.  
  For example: 
  - `l._1:gsub("a", "e")` replaces all occurrences of "a" in the text of the
  first argnode with "e", or
  - `l._1 .. l._2` concatenates text of the first and second argnode.
  If an argnode contains multiple lines of text, they are concatenated with
  `"\n"` prior to any operation.  
- `argnodes`, a [Node Reference](#node-reference), just like in function- and
  dynamicNode.

There are many examples for `lambda` in `Examples/snippets.lua`

## Match
`match` can insert text based on a predicate (again, a shorthand for `functionNode`).

`match(argnodes, condition, then, else)`:

* `argnode`: A single [Node Reference](#node-reference). May not be nil, or
	a table.
* `condition` may be either of
  * `string`: interpreted as a Lua pattern. Matched on the `\n`-joined (in case
    it's multiline) text of the first argnode (`args[1]:match(condition)`).
  * `function`: `fn(args, snip) -> bool`: takes the same parameters as the
    `functionNode`-function, any value other than nil or false is interpreted
    as a match.
  * `lambda`: `l._n` is the `\n`-joined text of the nth argnode.  
    Useful if string manipulations have to be performed before the string is matched.  
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

* `match(n, "^ABC$", "A")`

  ```lua
    s("extras1", {
      i(1), t { "", "" }, m(1, "^ABC$", "A")
    })
  ```
  Inserts "A" if the node with jump-index `n` matches "ABC" exactly, nothing otherwise.

  <!-- panvimdoc-ignore-start -->

  ![extras1](https://user-images.githubusercontent.com/25300418/184359431-50f90599-3db0-4df0-a3a9-27013e663649.gif)

  <!-- panvimdoc-ignore-end -->

* `match(n, lambda._1:match(lambda._1:reverse()), "PALINDROME")`

  ```lua
  s("extras2", {
    i(1, "INPUT"), t { "", "" }, m(1, l._1:match(l._1:reverse()), "PALINDROME")
  })
  ```
  Inserts `"PALINDROME"` if i(1) contains a palindrome.

  <!-- panvimdoc-ignore-start -->

  ![extras2](https://user-images.githubusercontent.com/25300418/184359435-21e4de9f-c56b-4ee1-bff4-331b68e1c537.gif)

  <!-- panvimdoc-ignore-end -->
* `match(n, lambda._1:match("^" .. lambda._2 .. "$"), lambda._1:gsub("a", "e"))`

  ```lua
  s("extras3", {
    i(1), t { "", "" }, i(2), t { "", "" },
    m({ 1, 2 }, l._1:match("^" .. l._2 .. "$"), l._1:gsub("a", "e"))
  })
  ```
  This inserts the text of the node with jump-index 1, with all occurrences of
  `a` replaced with `e`, if the second insertNode matches the first exactly.

  <!-- panvimdoc-ignore-start -->

  ![extras3](https://user-images.githubusercontent.com/25300418/184359436-515ca1cc-207f-400d-98ba-39fa166e22e4.gif)

  <!-- panvimdoc-ignore-end -->

## Repeat

Inserts the text of the passed node.

`rep(node_reference)`
- `node_reference`, a single [Node Reference](#node-reference).

```lua
s("extras4", { i(1), t { "", "" }, extras.rep(1) })
```

<!-- panvimdoc-ignore-start -->

![extras4](https://user-images.githubusercontent.com/25300418/184359193-6525d60d-8fd8-4fbd-9d3f-e3e7d5a0259f.gif)

<!-- panvimdoc-ignore-end -->

## Partial

Evaluates a function on expand and inserts its value.

`partial(fn, params...)`
- `fn`: any function
- `params`: varargs, any, will be passed to `fn`.

For example `partial(os.date, "%Y")` inserts the current year on expansion.


```lua
s("extras5", { extras.partial(os.date, "%Y") })
```

<!-- panvimdoc-ignore-start -->

![extras5](https://user-images.githubusercontent.com/25300418/184359206-6c25fc3b-69e1-4529-9ebf-cb92148f3597.gif)

<!-- panvimdoc-ignore-end -->

## Nonempty
Inserts text if the referenced node doesn't contain any text.

`nonempty(node_reference, not_empty, empty)`:

- `node_reference`, a single [Node Reference](#node-reference).  
- `not_empty`, `string`: inserted if the node is not empty.
- `empty`, `string`: inserted if the node is empty.

```lua
s("extras6", { i(1, ""), t { "", "" }, extras.nonempty(1, "not empty!", "empty!") })
```

<!-- panvimdoc-ignore-start -->

![extras6](https://user-images.githubusercontent.com/25300418/184359213-79a71d1e-079c-454d-a092-c231ac5a98f9.gif)

<!-- panvimdoc-ignore-end -->

## Dynamic Lambda

Pretty much the same as lambda, but it inserts the resulting text as an
insertNode, and, as such, it can be quickly overridden.

`dynamic_lambda(jump_indx, lambda, node_references)`
- `jump_indx`, as usual, the jump-index.

The remaining arguments carry over from lambda.

```lua
s("extras7", { i(1), t { "", "" }, extras.dynamic_lambda(2, l._1 .. l._1, 1) })
```

<!-- panvimdoc-ignore-start -->

![extras7](https://user-images.githubusercontent.com/25300418/184359221-1f090895-bc59-44b0-a984-703bf8d278a3.gif)

<!-- panvimdoc-ignore-end -->

## `fmt`

Authoring snippets can be quite clunky, especially since every second node is
probably a `textNode`, inserting a small number of characters between two more
complicated nodes.

`fmt` can be used to define snippets in a much more readable way. This is
achieved by borrowing (as the name implies) from `format`-functionality (our
syntax is very similar to
[python's](https://docs.python.org/3/library/stdtypes.html#str.format)).

`fmt` accepts a string and a table of nodes. Each occurrence of a delimiter pair
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
  s("example5", fmt([[
    line1: no indent

      line3: 2 space -> 1 indent ('\t')
        line4: 4 space -> 2 indent ('\t\t')
  ]], {}, {
    indent_string = "  "
  }))
  -- NOTE: [[\t]] means '\\t'
  s("example6", fmt([[
    line1: no indent

    \tline3: '\\t' -> 1 indent ('\t')
    \t\tline4: '\\t\\t' -> 2 indent ('\t\t')
  ]], {}, {
    indent_string = [[\t]]
  }))
})
```

<!-- panvimdoc-ignore-start -->

![`fmt`](https://user-images.githubusercontent.com/25300418/184359228-d30df745-0fe8-49df-b28d-662e7eb050ec.gif)

<!-- panvimdoc-ignore-end -->

One important detail here is that the position of the delimiters does not, in
any way, correspond to the jump-index of the nodes!

`fmt(format:string, nodes:table of nodes, opts:table|nil) -> table of nodes`

* `format`: a string. Occurrences of `{<somekey>}` ( `{}` are customizable; more
  on that later) are replaced with `content[<somekey>]` (which should be a
  node), while surrounding text becomes `textNode`s.  
  To escape a delimiter, repeat it (`"{{"`).  
  If no key is given (`{}`) are numbered automatically:  
  `"{} ? {} : {}"` becomes `"{1} ? {2} : {3}"`, while
  `"{} ? {3} : {}"` becomes `"{1} ? {3} : {4}"` (the count restarts at each
  numbered placeholder).
  If a key appears more than once in `format`, the node in
  `content[<duplicate_key>]` is inserted for the first, and copies of it for
  subsequent occurrences.
* `nodes`: just a table of nodes.
* `opts`: optional arguments:
  * `delimiters`: string, two characters. Change `{}` to some other pair, e.g.
  	`"<>"`.
  * `strict`: Warn about unused nodes (default true).
  * `trim_empty`: remove empty (`"%s*"`) first and last line in `format`. Useful
  	when passing multiline strings via `[[]]` (default true).
  * `dedent`: remove indent common to all lines in `format`. Again, makes
  	passing multiline-strings a bit nicer (default true).
  * `indent_string`: convert `indent_string` at beginning of each line to unit
        indent ('\t'). This is applied after `dedent`. Useful when using
        multiline string in `fmt`. (default empty string, disabled)
  * `repeat_duplicates`: repeat nodes when a key is reused instead of copying
        the node if it has a jump-index, refer to [Basics-Jump-Index](#jump-index) to
        know which nodes have a jump-index (default false).

There is also `require("luasnip.extras.fmt").fmta`. This only differs from `fmt`
by using angle brackets (`<>`) as the default delimiter.

## Conditions

This module (`luasnip.extras.condition`) contains functions that can be passed to
a snippet's `condition` or `show_condition`. These are grouped accordingly into
`luasnip.extras.conditions.expand` and `luasnip.extras.conditions.show`:

**`expand`**:

- `line_begin`: only expand if the cursor is at the beginning of the line.
- `trigger_not_preceded_by(pattern)`: only expand if the character before the
  trigger does not match `pattern`. This is a generalization of `wordTrig`,
  which can be implemented as `trigger_not_preceded_by("[%w_]")`, and is
  available as `word_trig_condition`.

**`show`**:

- `line_end`: only expand at the end of the line.
- `has_selected_text`: only expand if there's selected text stored after pressing
  `store_selection_keys`. 

Additionally, `expand` contains all conditions provided by `show`.

### Condition Objects

`luasnip.extras.conditions` also contains condition objects. These can, just
like functions, be passed to `condition` or `show_condition`, but can also be
combined with each other into logical expressions:

- `-c1 -> not c1`
- `c1 * c2 -> c1 and c2`
- `c1 + c2 -> c1 or c2`
- `c1 - c2 -> c1 and not c2`: This is similar to set differences:
  `A \ B = {a in A | a not in B}`. This makes `-(a + b) = -a - b` an identity
  representing de Morgan's law: `not (a or b) = not a and not b`. However,
  since boolean algebra lacks an additive inverse, `a + (-b) = a - b` does not
  hold. Thus, this is NOT the same as `c1 + (-c2)`.
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

The conditions provided in `show` and `expand` are already condition objects. To
create new ones, use
`require("luasnip.extras.conditions").make_condition(condition_fn)`


## On The Fly-Snippets

Sometimes it's desirable to create snippets tailored for exactly the current
situation. For example inserting repetitive, but just slightly different
invocations of some function, or supplying data in some schema.

On-the-fly snippets enable exactly this use case: they can be quickly created
and expanded with as little disruption as possible.  

Since they should mainly fast to write and don't necessarily need all bells and
whistles, they don't make use of `lsp/textmate-syntax`, but a more simplistic one:  

* `$anytext` denotes a placeholder (`insertNode`) with text "anytext". The text
  also serves as a unique key: if there are multiple placeholders with the same
  key, only the first will be editable, the others will just mirror it.  
* ... That's it. `$` can be escaped by preceding it with a second `$`, all other
  symbols will be interpreted literally.

There is currently only one way to expand on-the-fly snippets:  
`require('luasnip.extras.otf').on_the_fly("<some-register>")` will interpret
whatever text is in the register `<some-register>` as a snippet, and expand it
immediately.
The idea behind this mechanism is that it enables a very immediate way of
supplying and retrieving (expanding) the snippet: write the snippet-body into
the buffer, cut/yank it into some register, and call `on_the_fly("<register>")`
to expand the snippet.  

Here's one set of example keybindings:

```vim
" in the first call: passing the register is optional since `on_the_fly`
" defaults to the unnamed register, which will always contain the previously cut
" text.
vnoremap <c-f>  "ec<cmd>lua require('luasnip.extras.otf').on_the_fly("e")<cr>
inoremap <c-f>  <cmd>lua require('luasnip.extras.otf').on_the_fly("e")<cr>
```

Obviously, `<c-f>` is arbitrary and can be changed to any other key combo.
Another interesting application is allowing multiple on-the-fly snippets at the
same time by retrieving snippets from multiple registers:
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

## select_choice

It's possible to leverage `vim.ui.select` for selecting a choice directly,
without cycling through the available choices.  
All that is needed for this is calling
`require("luasnip.extras.select_choice")`, most likely via some keybinding, e.g.

```vim
inoremap <c-u> <cmd>lua require("luasnip.extras.select_choice")()<cr>
```
while inside a `choiceNode`.  
The `opts.kind` hint for `vim.ui.select` will be set to `luasnip`.

<!-- panvimdoc-ignore-start -->

![select_choice](https://user-images.githubusercontent.com/25300418/184359342-c8d79d50-103c-44b7-805f-fe75294e62df.gif)

<!-- panvimdoc-ignore-end -->

## Filetype-Functions

Contains some utility functions that can be passed to the `ft_func` or
`load_ft_func`-settings.

* `from_filetype`: the default for `ft_func`. Simply returns the filetype(s) of
  the buffer.
* `from_cursor_pos`: uses tree-sitter to determine the filetype at the cursor.
  With that, it's possible to expand snippets in injected regions, as long as
  the tree-sitter parser supports them.
  If this is used in conjunction with `lazy_load`, extra care must be taken that
  all the filetypes that can be expanded in a given buffer are also returned by
  `load_ft_func` (otherwise their snippets may not be loaded).
  This can easily be achieved with `extend_load_ft`.
* `extend_load_ft`: `fn(extend_ft:map) -> fn`
  A simple solution to the problem described above is loading more filetypes
  than just that of the target buffer when `lazy_load`ing. This can be done
  ergonomically via `extend_load_ft`: calling it with a table where the keys are
  filetypes, and the values are the filetypes that should be loaded additionally
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

## Postfix-Snippet

Postfix snippets, famously used in 
[rust analyzer](https://rust-analyzer.github.io/) and various IDEs, are a type
of snippet which alters text before the snippet's trigger. While these
can be implemented using `regTrig` snippets, this helper makes the process easier
in most cases.

The simplest example, which surrounds the text preceding the `.br` with
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
})
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
    preceding the trigger match as the end of the string.

Some other match strings, including the default, are available from the postfix
module. `require("luasnip.extras.postfix).matches`:

- `default`: `[%w%.%_%-%"%']+$`
- `line`: `^.+$`

The second argument is identical to the second argument for `s`, that is, a
table of nodes.

The optional third argument is the same as the third (`opts`) argument to the
`s` function, but with one difference:

The postfix snippet works using a callback on the pre_expand event of the
snippet. If you pass a callback on the pre_expand event (structure example
below) it will get run after the builtin callback.

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

## Treesitter-Postfix-Snippet

Instead of triggering a postfix-snippet when some pattern matches in front of
the trigger, it might be useful to match if some specific tree-sitter nodes
surround/are in front of the trigger.  
While this functionality can also be implemented by a custom
`resolveExpandParams`, this helper simplifies the common cases.  

This matching of tree-sitter nodes can be done either

* by providing a query and the name of the capture that should be in front of
  the trigger (in most cases, the complete match, but requiring specific nodes
  before/after the matched node may be useful as well), or
* by providing a function that manually walks the node-tree, and returns the
  node in front of the trigger on success (for increased flexibility).

A simple example, which surrounds the previous node's text preceding the `.mv`
with `std::move()` in C++ files, looks like:

```lua
local treesitter_postfix = require("luasnip.extras.treesitter_postfix").treesitter_postfix

treesitter_postfix({
    trig = ".mv",
    matchTSNode = {
        query = [[
            [
              (call_expression)
              (identifier)
              (template_function)
              (subscript_expression)
              (field_expression)
              (user_defined_literal)
            ] @prefix
        ]]
        query_lang = "cpp"
    },
},{
    f(function(_, parent)
        local node_content = table.concat(parent.snippet.env.LS_TSMATCH, '\n')
        local replaced_content = ("std::move(%s)"):format(node_content)
        return vim.split(ret_str, "\n", { trimempty = false })
    end)
})
```

`LS_TSMATCH` is the tree-sitter-postfix equivalent to `POSTFIX_MATCH`, and is
populated with the match (in this case the text of a tree-sitter-node) in front
of the trigger.

<!-- panvimdoc-ignore-start -->

![tree-sitter-postfix](https://user-images.githubusercontent.com/6359934/260666471-a60589aa-4454-4a9c-a103-87775c2cdf04.gif)

<!-- panvimdoc-ignore-end -->

The arguments to `treesitter_postfix` are identical to the arguments to `s` but
with a few extra options.

The first argument has to be a table, which defines at least `trig` and
`matchTSNode`. All keys from the regular `s` may be set here (except for
`wordTrig`, which will be ignored), and additionally the following:

- `reparseBuffer`, `string?`: Sometimes the trigger may interfere with
  tree-sitter recognizing queries correctly. With this option, the trigger may
  either be removed from the live-buffer (`"live"`), from a copy of the buffer
  (`"copy"`), or not at all (`nil`).
- `matchTSNode`: How to determine whether there is a matching node in front of
  the cursor. There are two options:
  * `fun(parser: LuaSnip.extra.TSParser, pos: { [1]: number, [2]: number }): LuaSnip.extra.NamedTSMatch?, TSNode?`
    Manually determine whether there is a matching node that ends just before
    `pos` (the beginning of the trigger).  
    Return `nil,nil` if there is no match, otherwise first return a table
    mapping names to nodes (the text, position and type of these will be
    provided via `snip.env`), and second the node that is the matched node.
  * `LuaSnip.extra.MatchTSNodeOpts`, which represents a query and provides all
    captures of the matched pattern in `NamedTSMatch`. It contains the following
    options:
    * `query`, `string`: The query, in textual form.
    * `query_name`, `string`: The name of the runtime-query to be used (passed
      to `query.get()`), defaults to `"luasnip"` (so one could create a
      file which only contains queries used by luasnip, like
      `$CONFDIR/queries/<lang>/luasnip.scm`, which might make sense to define
      general concepts independent of a single snippet).  
      `query` and `query_name` are mutually exclusive, only one of both shall be
      defined.  
    * `query_lang`, `string`: The language of the query. This is the only
      required parameter to this function, since there's no sufficiently
      straightforward way to determine the language of the query for us.
      Consider using `extend_override` to define a `ts_postfix`-function that
      automatically fills in the language for the filetype of the snippet-file.
    * `match_captures`, `string|string[]`: The capture(s) to use for determining
      the actual prefix (so the node that should be immediately in front of the
      trigger). This defaults to just `"prefix"`.
    * `select`, `string?|fun(): LuaSnip.extra.MatchSelector`: Since there may be
      multiple matching captures in front of the cursor, there has to be some
      way to select the node that will actually be used.  
      If this is a string, it has to be one of "any", "shortest", or "longest",
      which mean that any, the shortest, or the longest match is used.  
      If it is a function, it must return a table with two fields, `record` and
      `retrieve`. `record` is called with a `TSMatch` and a potential node for the
      `TSMatch`, and may return `true` to abort the selection-procedure.
      `retrieve` must return either a `TSMatch`-`TSNode`-tuple (which is used as the
      match) or `nil`, to signify that there is no match.  
      `lua/luasnip/extras/_treesitter.lua` contains the table
      `builtin_tsnode_selectors`, which contains the implementations for
      any/shortest/longest, which can be used as examples for more complicated
      custom-selectors.

The text of the matched node can be accessed as `snip.env.LS_TSMATCH`.  
The text of the nodes returned as `NamedTSMatch` can be accessed as
`snip.env.LS_TSCAPTURE_<node-name-in-caps>`, and their range and type as
`snip.env.LS_TSDATA.<node-name-NOT-in-caps>.range/type` (where range is a
tuple of row-col-tuples, both 0-indexed).  

For a query like
```scm
(function_declaration
  name: (identifier) @fname
  parameters: (parameters) @params
  body: (block) @body
) @prefix
```

matched against

```lua
function add(a, b)
    return a + b
end
```

`snip.env` would contain:

* `LS_TSMATCH`: `{ "function add(a, b)", "\treturn a + b", "end" }`
* `LS_TSDATA`:
  ```lua
  {
    body = {
      range = { { 1, 1 }, { 1, 13 } },
      type = "block"
    },
    fname = {
      range = { { 0, 9 }, { 0, 12 } },
      type = "identifier"
    },
    params = {
      range = { { 0, 12 }, { 0, 18 } },
      type = "parameters"
    },
    prefix = {
      range = { { 0, 0 }, { 2, 3 } },
      type = "function_declaration"
    }
  }
  ```
* `LS_TSCAPTURE_FNAME`: `{ "add" }`
* `LS_TSCAPTURE_PARAMS`: `{ "(a, b)" }`
* `LS_TSCAPTURE_BODY`: `{ "return a + b" }`
* `LS_TSCAPTURE_PREFIX`: `{ "function add(a, b)", "\treturn a + b", "end" }`

(note that all variables containing text of nodes are string-arrays, one entry
for each line)

There is one important caveat when accessing `LS_TSDATA` in
function/dynamicNodes: It won't contain the values as specified here while
generating docstrings (in fact, it won't even be a table).  
Since docstrings have to be generated without any runtime-information, we just
have to provide dummy-data in `env`, which will be some kind of string related
to the name of the environment variable.  
Since the structure of `LS_TSDATA` obviously does not fit that model, we can't
really handle it in a nice way (at least yet). So, for now, best include a check
like `local static_evaluation = type(env.LS_TSDATA) == "string"`, and behave
accordingly if `static_evaluation` is true (for example, return some value
tailored for displaying it in a docstring).

One more example, which actually uses a few captures:
```lua
ts_post({
    matchTSNode = {
        query = [[
            (function_declaration
              name: (identifier) @fname
              parameters: (parameters) @params
              body: (block) @body
            ) @prefix
        ]],
        query_lang = "lua",
    },
    trig = ".var"
}, fmt([[
    local {} = function{}
        {}
    end
]], {
    l(l.LS_TSCAPTURE_FNAME),
    l(l.LS_TSCAPTURE_PARAMS),
    l(l.LS_TSCAPTURE_BODY),
}))
```
<!-- panvimdoc-ignore-start -->

![tree-sitter-postfix-2](https://github.com/L3MON4D3/LuaSnip/assets/41961280/37868d75-3240-4a47-bd80-5e8666778b71)

<!-- panvimdoc-ignore-end -->

The module `luasnip.extras.treesitter_postfix` contains a few functions that may
be useful for creating more efficient ts-postfix-snippets.  
Nested in `builtin.tsnode_matcher` are:

* `fun find_topmost_types(types: string[]): MatchTSNodeFunc`: Generates
  a `LuaSnip.extra.MatchTSNodeFunc` which returns the last parent whose type
  is in `types`.
* `fun find_first_types(types: string[]): MatchTSNodeFunc`: Similar to
  `find_topmost_types`, only this one matches the first parent whose type is in
  types.
* `find_nth_parent(n: number): MatchTSNodeFunc`: Simply matches the `n`-th
  parent of the innermost node in front of the trigger.

With `find_topmost_types`, the first example can be implemented more
efficiently (without needing a whole query):
```lua
local postfix_builtin = require("luasnip.extras.treesitter_postfix").builtin

ls.add_snippets("all", {
	ts_post({
		matchTSNode = postfix_builtin.tsnode_matcher.find_topmost_types({
			"call_expression",
			"identifier",
			"template_function",
			"subscript_expression",
			"field_expression",
			"user_defined_literal"
		}),
		trig = ".mv"
	}, {
		l(l_str.format("std::move(%s)", l.LS_TSMATCH))
	})
}, {key = "asdf"})
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

However, this doesn't have to be the case. For example, you can implement your
own printer function that returns a table representation of the snippets
**but** you would have to then implement your own display function or some
other function in order to return the result as a string.

An `options` table, which has some core functionality that can be used
to customize 'common' settings, is provided.

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

## Snippet Location

This module can consume a snippets [source](#source), more specifically, jump to
the location referred by it.  
This is primarily implemented for snippet which got their source from one of the
loaders, but might also work for snippets where the source was set manually.  

`require("luasnip.extras.snip_location")`:

* `snip_location.jump_to_snippet(snip, opts)`
  Jump to the definition of `snip`.
  * `snip`: a snippet with attached source-data.
  * `opts`: `nil|table`, optional arguments, valid keys are:
    * `hl_duration_ms`: `number`, duration for which the definition should be highlighted,
      in milliseconds. 0 disables the highlight.
    * `edit_fn`: `function(file)`, this function will be called with the file
      the snippet is located in, and is responsible for jumping to it.  
      We assume that after it has returned, the current buffer contains `file`.
* `snip_location.jump_to_active_snippet(opts)`
  Jump to definition of active snippet.
  * `opts`: `nil|table`, accepts the same keys as the `opts`-parameter of
    `jump_to_snippet`.


# Extend Decorator

Most of LuaSnip's functions have some arguments to control their behavior.  
Examples include `s`, where `wordTrig`, `regTrig`, ... can be set in the first
argument to the function, or `fmt`, where the delimiter can be set in the third
argument.  
This is all good and well, but if these functions are often used with
non-default settings, it can become cumbersome to always explicitly set them.

This is where the `extend_decorator` comes in:
it can be used to create decorated functions which always extend the arguments
passed directly with other previously defined ones.

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
(This is not limited to LuaSnip's functions; although, for usage outside of
LuaSnip, best copy the source file: `/lua/luasnip/util/extend_decorator.lua`).

`register(fn, ...)`:

* `fn`: the function.
* `...`: any number of tables. Each specifies how to extend an argument of `fn`.
  The tables accept:
  * `arg_indx`, `number` (required): the position of the parameter to override.
  * `extend`, `fn(arg, extend_value) -> effective_arg` (optional): this function
    is used to extend the arguments passed to the decorated function.
    It defaults to a function which just extends the arguments table with the
    extend table (accepts `nil`).
    This extend behavior is adaptable to accommodate `s`, where the first
    argument may be string or table.

`apply(fn, ...) -> decorated_fn`:

* `fn`: the function to decorate.
* `...`: The values to extend with. These should match the descriptions passed
  in `register` (the argument first passed to `register` will be extended with
  the first value passed here).

One more example for registering a new function:
```lua
local function somefn(arg1, arg2, opts1, opts2)
	-- not important
end

-- note the reversed arg_indx!!
extend_decorator.register(somefn, {arg_indx=4}, {arg_indx=3})
local extended = extend_decorator.apply(somefn,
	{key = "opts2 is extended with this"},
	{key = "and opts1 with this"})
extended(...)
```

# LSP-Snippets

LuaSnip is capable of parsing LSP-style snippets using
`ls.parser.parse_snippet(context, snippet_string, opts)`:
```lua
ls.parser.parse_snippet({trig = "lsp"}, "$1 is ${2|hard,easy,challenging|}")
```

<!-- panvimdoc-ignore-start -->

![LSP](https://user-images.githubusercontent.com/25300418/184359304-eb9c9eb4-bd38-4db9-b412-792391e9c21d.gif)

<!-- panvimdoc-ignore-end -->

`context` can be:
  - `string|table`: treated like the first argument to `ls.s`, `parse_snippet`
    returns a snippet.
  - `number`: `parse_snippet` returns a snippetNode, with the position
    `context`.
  - `nil`: `parse_snippet` returns a flat table of nodes. This can be used
    like `fmt`.

Nested placeholders(`"${1:this is ${2:nested}}"`) will be turned into
choiceNodes with:
  - the given snippet(`"this is ${1:nested}"`) and
  - an empty insertNode

<!-- panvimdoc-ignore-start -->

![`lsp2`](https://user-images.githubusercontent.com/25300418/184359306-c669d3fa-7ae5-4c07-b11a-34ae8c4a17ac.gif)

<!-- panvimdoc-ignore-end -->

This behavior can be modified by changing `parser_nested_assembler` in
`ls.setup()`.


LuaSnip will also modify some snippets that it is incapable of representing
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
`ls.lsp_expand`: it might prevent correct expansion of snippets sent by LSP.

## SnipMate Parser

It is furthermore possible to parse SnipMate snippets (this includes support for
Vim script-evaluation!!)

SnipMate snippets need to be parsed with a different function,
`ls.parser.parse_snipmate`:
```lua
ls.parser.parse_snipmate("year", "The year is `strftime('%Y')`")
```

`parse_snipmate` accepts the same arguments as `parse_snippet`, only the
snippet body is parsed differently.

## Transformations

To apply
[Variable/Placeholder-transformations](https://code.visualstudio.com/docs/editor/userdefinedsnippets#_variable-transforms),
LuaSnip needs to apply ECMAScript regular expressions.
This is implemented by relying on [jsregexp](https://github.com/kmarius/jsregexp).

The easiest (but potentially error-prone) way to install it is by calling `make
install_jsregexp` in the repository root.

This process can be automated by `packer.nvim`:
```lua
use { "L3MON4D3/LuaSnip", run = "make install_jsregexp" }
```

If this fails, first open an issue :P, and then try installing the
`jsregexp`-LuaRock. This is also possible via 
`packer.nvim`, although actual usage may require a small workaround, see
[here](https://github.com/wbthomason/packer.nvim/issues/593) or
[here](https://github.com/wbthomason/packer.nvim/issues/358).  

Alternatively, `jsregexp` can be cloned locally, `make`d, and the resulting
`jsregexp.so` placed in some place where Neovim can find it (probably
`~/.config/nvim/lua/`).

If `jsregexp` is not available, transformations are replaced by a simple copy.

# Variables

All `TM_something`-variables are supported with two additions:
`LS_SELECT_RAW` and `LS_SELECT_DEDENT`. These were introduced because
`TM_SELECTED_TEXT` is designed to be compatible with VSCode's behavior, which
can be counterintuitive when the snippet can be expanded at places other than
the point where selection started (or when doing transformations on selected text).
Besides those we also provide `LS_TRIGGER` which contains the trigger of the snippet,
and  `LS_CAPTURE_n` (where n is a positive integer) that contains the n-th capture
when using a regex with capture groups as `trig` in the snippet definition.

All variables can be used outside of LSP parsed snippets as their values are
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
hitting `<Tab>` while in visual mode will populate the `*SELECT*`-vars for the next
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
    (in this case, if the value is a function it will be executed lazily once per snippet expansion).
    * `init`: `fn(info: table)->map[string, EnvVal]`  Returns
        a table of variables that will set to the environment of the snippet on expansion,
        use this for vars that have to be calculated in that moment or that depend on each other.
        The `info` table argument contains `pos` (0-based position of the cursor on expansion),
        the `trigger` of the snippet and the `captures` list.
    * `eager`: `list[string]` names of variables that will be taken from `vars` and appended eagerly (like those in `init`)
    * `multiline_vars`: `(fn(name:string)->bool)|map[string, bool]|bool|string[]` Says if certain vars are a table or just a string,
        can be a function that get's the name of the var and returns true if the var is a key,
        a list of vars that are tables or a boolean for the full namespace, it's false by default. Refer to
        [issue#510](https://github.com/L3MON4D3/LuaSnip/issues/510#issuecomment-1209333698) for more information.

The four fields of `opts` are optional but you need to provide either `init` or  `vars`, and `eager` can't be without `vars`.
Also, you can't use namespaces that override default vars.


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
LSP snippets as `$VAR_NAME`.

The LSP specification states:

----

With `$name` or `${name:default}` you can insert the value of a variable.  
When a variable isn't set, its default or the empty string is inserted.
When a variable is unknown (that is, its name isn't defined) the name of the variable is inserted and it is transformed into a placeholder.

----

The above necessitates a differentiation between `unknown` and `unset` variables:

For LuaSnip, a variable `VARNAME` is `unknown` when `env.VARNAME` returns `nil` and `unset`
if it returns an empty string.

Consider this when adding environment variables which might be used in LSP snippets.

# Loaders

Luasnip is capable of loading snippets from different formats, including both
the well-established VSCode and SnipMate format, as well as plain Lua files for
snippets written in Lua.

All loaders (except the `vscode-standalone-loader`) share a similar interface:
`require("luasnip.loaders.from_{vscode,snipmate,lua}").{lazy_,}load(opts:table|nil)`

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
  - `snipmate`: similar to Lua, but the directory has to be `"snippets"`.
  - `vscode`: any directory in `runtimepath` that contains a
    `package.json` contributing snippets.
- `lazy_paths`: behaves essentially like `paths`, with two exceptions: if it is
  `nil`, it does not default to `runtimepath`, and the paths listed here do not
  need to exist, and will be loaded on creation.  
  LuaSnip will do its best to determine the path that this should resolve to,
  but since the resolving we do is not very sophisticated it may produce
  incorrect paths. Definitely check the log if snippets are not loaded as
  expected.
- `exclude`: List of languages to exclude, empty by default.
- `include`: List of languages to include, includes everything by default.
- `{override,default}_priority`: These keys are passed straight to the
  `add_snippets`-calls (documented in [API](#api)) and can therefore change the
  priority of snippets loaded from some collection (or, in combination with
  `{in,ex}clude`, only some of its snippets).
- `fs_event_providers`: `table<string, boolean>?`, specifies which mechanisms
  should be used to watch files for updates/creation.  
  If `autocmd` is set to `true`, a `BufWritePost`-hook watches files of this
  collection, if `libuv` is set, the `file-watcher-api` exposed by `libuv` is used
  to watch for updates.  
  Use `libuv` if you want snippets to update from other Neovim-instances, and
  `autocmd` if the collection resides on a file system where the `libuv`-watchers
  may not work correctly. Or, of course, just enable both :D  
  By default, only `autocmd` is enabled.

While `load` will immediately load the snippets, `lazy_load` will defer loading until
the snippets are actually needed (whenever a new buffer is created, or the
filetype is changed LuaSnip actually loads `lazy_load`ed snippets for the
filetypes associated with this buffer. This association can be changed by
customizing `load_ft_func` in `setup`: the option takes a function that, passed
a `bufnr`, returns the filetypes that should be loaded (`fn(bufnr) -> filetypes
(string[])`)).  

All of the loaders support reloading, so simply editing any file contributing
snippets will reload its snippets (according to `fs_event_providers` in the
instance where the file was edited, or in other instances as well).

As an alternative (or addition) to automatic reloading, LuaSnip can also process
manual updates to files: Call `require("luasnip.loaders").reload_file(path)` to
reload the file at `path`.  
This may be useful when the collection is controlled by some other plugin, or
when enabling the other reload-mechanisms is for some reason undesirable
(performance? minimalism?).

For easy editing of these files, LuaSnip provides a `vim.ui.select`-based dialog
([Loaders-edit_snippets](#edit_snippets)) where first the filetype, and then the
file can be selected.

## Snippet-specific filetypes
Some loaders (`vscode`,`lua`) support giving snippets generated in some file their
own filetype (`vscode` via `scope`, `lua` via the underlying `filetype`-option for
snippets). These snippet-specific filetypes are not considered when determining
which files to `lazy_load` for some filetype, this is exclusively determined by
the `language` associated with a file in `vscodes`' `package.json`, and the
file/directory-name in `lua`.

 * This can be resolved relatively easily in `vscode`, where the `language`
   advertised in `package.json` can just be a superset of the `scope`s in the file.
 * Another simplistic solution is to set the language to `all` (in `lua`, it might
   make sense to create a directory `luasnippets/all/*.lua` to group these files
   together).
 * Another approach is to modify `load_ft_func` to load a custom filetype if the
   snippets should be activated, and store the snippets in a file for that
   filetype. This can be used to group snippets by e.g. framework, and load them
   once a file belonging to such a framework is edited.

**Example**:  
`react.lua`
```lua
return {
    s({filetype = "css", trig = ...}, ...),
    s({filetype = "html", trig = ...}, ...),
    s({filetype = "js", trig = ...}, ...),
}
```

`luasnip_config.lua`
```lua
load_ft_func = function(bufnr)
    if "<bufnr-in-react-framework>" then
        -- will load `react.lua` for this buffer
        return {"react"}
    else
        return require("luasnip.extras.filetype_functions").from_filetype_load
    end
end
```

See the [Troubleshooting-Adding Snippets-Loaders](#troubleshooting-adding-snippets-loaders)
section if one is having issues adding snippets via loaders.

## VS-Code

As a reference on the structure of these snippet libraries, see
[friendly-snippets](https://github.com/rafamadriz/friendly-snippets).

We support a small extension: snippets can contain LuaSnip-specific options in
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

Files with the extension `jsonc` will be parsed as `jsonc`,
[`json` with comments](https://code.visualstudio.com/docs/languages/json#_json-with-comments),
while `*.json` are parsed with a regular `json` parser, where comments are
disallowed. (the `json` parser is a bit faster, so don't default to `jsonc` if
it's not necessary).

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

### Standalone
Beside snippet-libraries provided by packages, `vscode` also supports another
format which can be used for project-local snippets, or user-defined snippets,
`.code-snippets`.  

The layout of these files is almost identical to that of the package-provided
snippets, but there is one additional field supported in the
snippet-definitions, `scope`, with which the filetype of the snippet can be set.
If `scope` is not set, the snippet will be added to the global filetype (`all`).

`require("luasnip.loaders.from_vscode").load_standalone(opts)`

- `opts`: `table`, can contain the following keys:
  - `path`: `string`, Path to the `*.code-snippets`-file that should be loaded.
    Just like the paths in `load`, this one can begin with a `"~/"` to be
    relative to `$HOME`, and a `"./"` to be relative to the
    Neovim config directory.
  - `{override,default}_priority`: These keys are passed straight to the
    `add_snippets`-calls (documented in [API](#api)) and can be used to change
    the priority of the loaded snippets.
  - `lazy`: `boolean`, if it is set, the file does not have to exist when
    `load_standalone` is called, and it will be loaded on creation.  
    `false` by default.

**Example**:
`a.code-snippets`:
```jsonc
{
    // a comment, since `.code-snippets` may contain jsonc.
    "c/cpp-snippet": {
        "prefix": [
            "trigger1",
            "trigger2"
        ],
        "body": [
            "this is $1",
            "my snippet $2"
        ],
        "description": "A description of the snippet.",
        "scope": "c,cpp"
    },
    "python-snippet": {
        "prefix": "trig",
        "body": [
            "this is $1",
            "a different snippet $2"
        ],
        "description": "Another snippet-description.",
        "scope": "python"
    },
    "global snippet": {
        "prefix": "trigg",
        "body": [
            "this is $1",
            "the last snippet $2"
        ],
        "description": "One last snippet-description.",
    }
}
```

This file can be loaded by calling
```lua
require("luasnip.loaders.from_vscode").load_standalone({path = "a.code-snippets"})
```

## SNIPMATE

Luasnip does not support the full SnipMate format: Only `./{ft}.snippets` and
`./{ft}/*.snippets` will be loaded. See
[honza/vim-snippets](https://github.com/honza/vim-snippets) for lots of
examples.

Like VSCode, the SnipMate format is also extended to make use of some of
LuaSnip's more advanced capabilities:
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
  compatible with LuaSnip
* We do not implement `eval` using \` (backtick). This may be implemented in the
  future.

## Lua

Instead of adding all snippets via `add_snippets`, it's possible to store them
in separate files and load all of those.  
The file-structure here is exactly the supported SnipMate-structure, e.g.
`<ft>.lua` or `<ft>/*.lua` to add snippets for the filetype `<ft>`.  

There are two ways to add snippets:

* the files may return two lists of snippets, the snippets in the first are all
  added as regular snippets, while the snippets in the second will be added as
  autosnippets (both are the defaults, if a snippet defines a different
  `snippetType`, that will have preference)
* snippets can also be appended to the global (only for these files - they are not
  visible anywhere else) tables `ls_file_snippets` and `ls_file_autosnippets`.
  This can be combined with a custom `snip_env` to define and add snippets with
  one function call:
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
  to be collected; they just have to be defined using the above `s` and `parse`.

As defining all of the snippet constructors (`s`, `c`, `t`, ...) in every file
is rather cumbersome, LuaSnip will bring some globals into scope for executing
these files.
By default, the names from [`luasnip.config.snip_env`][snip-env-src] will be used, but it's
possible to customize them by setting `snip_env` in `setup`.  

[snip-env-src]: https://github.com/L3MON4D3/LuaSnip/blob/master/lua/luasnip/config.lua#L22-L48


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


### Snip-Env Diagnostics
One side-effect of the injected globals is that language servers, for example
`lua-language-server`, do not know about them, which means that snippet-files
may have many diagnostics about missing symbols.

There are a few ways to fix this

* Add all variables in `snip_env` to `Lua.diagnostic.globals`:
  ```lua
  -- wherever your lua-language-server lsp settings are defined:
  settings = {
    Lua = {
        ...
        diagnostics = {
            globals = {
                "vim",
                "s",
                "c",
                "t",
                ...
            }
        }
    }
  }
  ```
  This will disable the warnings, but will do so in all files these lsp-settings
  are used with.  
  Similarly, adding `---@diagnostic disable: undefined-global` to the
  snippet-files is also possible, but this affects not only the variables in
  `snip_env`, but all variables, like local variable names that may be
  mistyped.
* A more complete, and only slightly more complicated solution is using
  `lua-language-server`'s
  [definition files](https://luals.github.io/wiki/definition-files/).  
  Add a file with the line `---@meta`, followed by the variables defined by the
  `snip_env` to any directory listed in the `workspace.library`-settings for
  `lua-langue-server` (one likely directory is `vim.fn.stdpath("config")/lua`,
  check `:checkhealth lsp` in a lua file to be sure).  
  ```lua
  ---@meta
  
  s = require("luasnip.nodes.snippet").S
  sn = require("luasnip.nodes.snippet").SN
  isn = require("luasnip.nodes.snippet").ISN
  t = require("luasnip.nodes.textNode").T
  i = require("luasnip.nodes.insertNode").I
  f = require("luasnip.nodes.functionNode").F
  c = require("luasnip.nodes.choiceNode").C
  d = require("luasnip.nodes.dynamicNode").D
  r = require("luasnip.nodes.restoreNode").R
  events = require("luasnip.util.events")
  k = require("luasnip.nodes.key_indexer").new_key
  ai = require("luasnip.nodes.absolute_indexer")
  extras = require("luasnip.extras")
  l = require("luasnip.extras").lambda
  rep = require("luasnip.extras").rep
  p = require("luasnip.extras").partial
  m = require("luasnip.extras").match
  n = require("luasnip.extras").nonempty
  dl = require("luasnip.extras").dynamic_lambda
  fmt = require("luasnip.extras.fmt").fmt
  fmta = require("luasnip.extras.fmt").fmta
  conds = require("luasnip.extras.expand_conditions")
  postfix = require("luasnip.extras.postfix").postfix
  types = require("luasnip.util.types")
  parse = require("luasnip.util.parser").parse_snippet
  ms = require("luasnip.nodes.multiSnippet").new_multisnippet
  ```

  While that allows the `snip_env`-variables to resolve correctly in
  snippet-files, it also resolves them in other lua files. This can be fixed by
  putting the file in a directory that is _not_ in `workspace.library` (create,
  for example, `vim.fn.stdpath("state")/luasnip-snip_env/`), and then adding its
  path to `workspace.library` only for snippet files, for example by putting a
  `.luarc.json` with the following content into all snippet-directories:
  ```json
  {
	"workspace.library": ["<state-stdpath>/luasnip-snip_env"]
  }
  ```

### Reloading when editing `require`'d files
While the `lua-snippet-files` will be reloaded on edit, this does not
automatically happen if a file the snippet-file depends on (e.g. via `require`)
is changed.  
Since this still may still be desirable, there are two functions exposed when a
file is loaded by the `lua-loader`: `ls_tracked_dofile` and
`ls_tracked_dopackage`. They perform like `dofile` and (almost like) `require`,
but both register the loaded file internally as a dependency of the
snippet-file, so it can be reloaded when the loaded file is edited.  As stated,
`ls_tracked_dofile` behaves exactly like `dofile`, but does the dependency-work
as well.  
`ls_tracked_dopackage` mimics `require` in that it does not take a path, but a
module-name like `"luasnip.loaders.from_lua"`, and then searches the
`runtimepath/lua`-directories, and `path` and `cpath` for the module.  
Unlike `require`, the file will not be cached, since that would complicate the
reload-on-edit-behavior.

## edit_snippets

To easily edit snippets for the current session, the files loaded by any loader
can be quickly edited via
`require("luasnip.loaders").edit_snippet_files(opts:table|nil)`

When called, it will open a `vim.ui.select`-dialog to select first a filetype,
and then (if there are multiple) the associated file to edit.

<!-- panvimdoc-ignore-start -->

![edit-select](https://user-images.githubusercontent.com/25300418/184359412-e6a1238c-d733-411c-b05d-8334ea993fbf.gif)

<!-- panvimdoc-ignore-end -->

`opts` contains four settings:

* `ft_filter`: `fn(filetype:string) -> bool`
  Optionally filter initially listed filetypes.
  `true` -> filetype will be listed, `false` -> not listed.
  Accepts all filetypes by default.
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

  This can be used to create a new snippet file for the current filetype:
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

# SnippetProxy

`SnippetProxy` is used internally to alleviate the upfront cost of
loading snippets from e.g. a SnipMate library or a VSCode package. This is
achieved by only parsing the snippet on expansion, not immediately after reading
it from some file.
`SnippetProxy` may also be used from Lua directly to get the same benefits:

This will parse the snippet on startup:
```lua
ls.parser.parse_snippet("trig", "a snippet $1!")
```

while this will parse the snippet upon expansion:
```lua
local sp = require("luasnip.nodes.snippetProxy")
sp("trig", "a snippet $1")
```

`sp(context, body, opts) -> snippetProxy`

- `context`: exactly the same as the first argument passed to `ls.s`.
- `body`: the snippet body.
- `opts`: accepts the same `opts` as `ls.s`, with some additions:
  - `parse_fn`: the function for parsing the snippet. Defaults to
    `ls.parser.parse_snippet` (the parser for LSP snippets), an alternative is
    the parser for SnipMate snippets (`ls.parser.parse_snipmate`).

# ext_opts

`ext_opts` can be used to set the `opts` (see `nvim_buf_set_extmark`) of the
extmarks used for marking node positions, either globally, per snippet or
per node.
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

In the above example, the text inside the insertNodes is highlighted in green if
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
entire snippet. For this, it's necessary to specify which kind of node a given
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
snippets.

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
However, the `ext_opts` here are only applied to the `insertNodes` inside this
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
highlight groups:

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

One problem that might arise when nested nodes are highlighted is that the
highlight of inner nodes should be visible, e.g. above that of nodes they are
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
Here the highlight of an insertNode nested directly inside a `choiceNode` is
always visible on top of it.


# Docstrings

Snippet docstrings can be queried using `snippet:get_docstring()`. The function
evaluates the snippet as if it was expanded regularly, which can be problematic
if e.g. a dynamicNode in the snippet relies on inputs other than
the argument nodes.
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
})
```

This snippet works fine because	`snippet.captures[1]` is always a number.
During docstring generation, however, `snippet.captures[1]` is `'$CAPTURES1'`,
which will cause an error in the functionNode.
Issues with `snippet.captures` can be prevented by specifying `docTrig` during
snippet-definition:

```lua
s({trig = "(%d)", regTrig = true, docTrig = "3"}, {
	f(function(args, snip)
		return string.rep("repeatme ", tonumber(snip.captures[1]))
	end, {})
})
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
})
```

Refer to [#515](https://github.com/L3MON4D3/LuaSnip/pull/515) for a
better example to understand `docTrig` and `docstring`.

# Docstring-Cache

Although generation of docstrings is pretty fast, it's preferable to not
redo it as long as the snippets haven't changed. Using
`ls.store_snippet_docstrings(snippets)` and its counterpart
`ls.load_snippet_docstrings(snippets)`, they may be serialized from or
deserialized into the snippets.
Both functions accept a table structured like this: `{ft1={snippets},
ft2={snippets}}`. Such a table containing all snippets can be obtained via
`ls.get_snippets()`.
`load` should be called before any of the `loader`-functions as snippets loaded
from VSCode style packages already have their `docstring` set (`docstrings`
wouldn't be overwritten, but there'd be unnecessary calls).

The cache is located at `stdpath("cache")/luasnip/docstrings.json` (probably
`~/.cache/nvim/luasnip/docstrings.json`).

# Events

Events can be used to react to some action inside snippets. These callbacks can
be defined per snippet (`callbacks`-key in snippet constructor), per-node by
passing them as `node_callbacks` in `node_opts`, or globally (autocommand).

`callbacks`: `fn(node[, event_args]) -> event_res`  
All callbacks receive the `node` associated with the event and event-specific
optional arguments, `event_args`.
`event_res` is only used in one event, `pre_expand`, where some properties of
the snippet can be changed. If multiple callbacks return `event_res`, we only
guarantee that one of them will be effective, not all of them.

`autocommand`:
Luasnip uses `User`-events. Autocommands for these can be registered using
```vim
au User SomeUserEvent echom "SomeUserEvent was triggered"
```

or
```lua
vim.api.nvim_create_autocommand("User", {
	pattern = "SomeUserEvent",
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
* `change_choice`: When the active choice in a `choiceNode` is changed.  
  `User-event`: `"LuasnipChangeChoice"`  
  `event_args`: none
* `pre_expand`: Called before a snippet is expanded. Modifying text is allowed,
  the expand-position will be adjusted so the snippet expands at the same
  position relative to existing text.  
  `User-event`: `"LuasnipPreExpand"`  
  `event_args`:
  * `expand_pos`: `{<row>, <column>}`, position at which the snippet will be
  	expanded. `<row>` and `<column>` are both 0-indexed.
  * `expand_pos_mark_id`: `number`, the id of the extmark LuaSnip uses to track
    `expand_pos`. This may be moved around freely.
  `event_res`:
  * `env_override`: `map string->(string[]|string)`, override or extend the
    snippet's environment (`snip.env`).

A pretty useless, beyond serving as an example here, application of these would
be printing e.g. the node's text after entering:

```lua
vim.api.nvim_create_autocmd("User", {
	pattern = "LuasnipInsertNodeEnter",
	callback = function()
		local node = require("luasnip").session.event_node
		print(table.concat(node:get_text(), "\n"))
	end
})
```

or some information about expansions:

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

# Cleanup
The function ls.cleanup()  triggers the `LuasnipCleanup` user event, that you
can listen to do some kind of cleaning in your own snippets; by default it will
empty the snippets table and the caches of the lazy_load.

# Logging
Luasnip uses logging to report unexpected program states, and information on
what's going on in general. If something does not work as expected, taking a
look at the log (and potentially increasing the log level) might give some good
hints towards what is going wrong.  

The log is stored in `<vim.fn.stdpath("log")>/luasnip.log`
(`<vim.fn.stdpath("cache")>/luasnip.log` for Neovim versions where
`stdpath("log")` does not exist), and can be opened by calling `ls.log.open()`. You can get the log path through `ls.log.log_location()`.
The log level (granularity of reported events) can be adjusted by calling
`ls.log.set_loglevel("error"|"warn"|"info"|"debug")`. `"debug"` has the highest
granularity, `"error"` the lowest, the default is `"warn"`.
You can also adjust the datetime formatting through the `ls.log.time_fmt` variable. By default, it uses the `'%X'` formatting, which results in the full time (hour, minutes and seconds) being shown.

Once this log grows too large (10MiB, currently not adjustable), it will be
renamed to `luasnip.log.old`, and a new, empty log created in its place. If
there already exists a `luasnip.log.old`, it will be deleted.

`ls.log.ping()` can be used to verify the log is working correctly: it will
print a short message to the log.

# Source
It is possible to attach, to a snippet, information about its source. This can
be done either by the various loaders (if it is enabled in `ls.setup`
([Config-Options](#config-options), `loaders_store_source`)), or manually. The
attached data can be used by [Extras-Snippet-Location](#snippet-location) to
jump to the definition of a snippet.  

It is also possible to get/set the source of a snippet via API:

`ls.snippet_source`:

* `get(snippet) -> source_data`:
  Retrieve the source-data of `snippet`. `source_data` always contains the key
  `file`, the file in which the snippet was defined, and may additionally
  contain `line` or `line_end`, the first and last line of the definition.
* `set(snippet, source)`:
  Set the source of a snippet.
  * `snippet`: a snippet which was added via `ls.add_snippets`.
  * `source`: a `source`-object, obtained from either `from_debuginfo` or
    `from_location`.
* `from_location(file, opts) -> source`:
  * `file`: `string`, The path to the file in which the snippet is defined.
  * `opts`: `table|nil`, optional parameters for the source.
    * `line`: `number`, the first line of the definition. 1-indexed.
    * `line_end`: `number`, the final line of the definition. 1-indexed.
* `from_debuginfo(debuginfo) -> source`:
  Generates source from the table returned by `debug.getinfo` (from now on
  referred to as `debuginfo`). `debuginfo` has to be of a frame of a function
  which is backed by a file, and has to contain this information, i.e. has to be
  generated by `debug.get_info(*, "Sl")` (at least `"Sl"`, it may also contain
  more info).

# Selection

Many snippets use the `$TM_SELECTED_TEXT` or (for LuaSnip, preferably
`LS_SELECT_RAW` or `LS_SELECT_DEDENT`) variable, which has to be populated by
selecting and then yanking (and usually also cutting) text from the buffer
before expanding.  

By default, this is disabled (as to not pollute keybindings which may be used
for something else), so one has to

* either set `cut_selection_keys` in `setup` (see
  [Config-Options](#config-options)).
* or map `ls.cut_keys` as the right-hand-side of a mapping
* or manually configure the keybinding. For this, create a new keybinding that
  1. `<Esc>`es to NORMAL (to populate the `<` and `>`-markers)
  2. calls `luasnip.pre_yank(<namedreg>)`
  3. yanks text to some named register `<namedreg>`
  4. calls `luasnip.post_yank(<namedreg>)`
  Take care that the yanking actually takes place between the two calls. One way
  to ensure this is to call the two functions via `<cmd>lua ...<Cr>`:
  ```lua
  vim.keymap.set("v", "<Tab>", [[<Esc><cmd>lua require("luasnip.util.select").pre_yank("z")<Cr>gv"zs<cmd>lua require('luasnip.util.select').post_yank("z")<Cr>]])
  ```
  The reason for this specific order is to allow us to take a snapshot of
  registers (in the pre-callback), and then restore them (in the post-callback)
  (so that we may get the visual selection directly from the register, which
  seems to be the most foolproof way of doing this).

# Config-Options

These are the settings you can provide to `luasnip.setup()`:

- `keep_roots`: Whether snippet-roots should be linked. See
  [Basics-Snippet-Insertion](#snippet-insertion) for more context.
- `link_roots`: Whether snippet-roots should be linked. See
  [Basics-Snippet-Insertion](#snippet-insertion) for more context.
- `exit_roots`: Whether snippet-roots should exit at reaching at their last
  node, `$0`. This setting is only valid for root snippets, not child snippets.
  This setting may avoid unexpected behavior by disallowing to jump earlier
  (finished) snippets. Check [Basics-Snippet-Insertion](#snippet-insertion) for
  more information on snippet-roots.
- `link_children`: Whether children should be linked. See
  [Basics-Snippet-Insertion](#snippet-insertion) for more context.
- `history` (deprecated): if not nil, `keep_roots`, `link_roots`, and
  `link_children` will be set to the value of `history`, and
  `exit_roots` will set to inverse value of `history`. This is just to ensure
  backwards-compatibility.
- `update_events`: Choose which events trigger an update of the active nodes'
  dependents. Default is just `'InsertLeave'`, `'TextChanged,TextChangedI'`
  would update on every change.
  These, like all other `*_events` are passed to `nvim_create_autocmd` as
  `events`, so they can be wrapped in a table, like
  ```lua
  ls.setup({
  	update_events = {"TextChanged", "TextChangedI"}
  })
  ```
- `region_check_events`: Events on which to leave the current snippet-root if
  the cursor is outside its' 'region'. Disabled by default, `'CursorMoved'`,
  `'CursorHold'` or `'InsertEnter'` seem reasonable.
- `delete_check_events`: When to check if the current snippet was deleted, and
  if so, remove it from the history. Off by default, `'TextChanged'` (perhaps
  `'InsertLeave'`, to react to changes done in Insert mode) should work just
  fine (alternatively, this can also be mapped using
  `<Plug>luasnip-delete-check`). 
- `cut_selection_keys`: Mapping for populating `TM_SELECTED_TEXT` and related
  variables (not set by default).  
  See [Selection](#selection) for more information.
- `store_selection_keys` (deprecated): same as `cut_selection_keys`
- `enable_autosnippets`: Autosnippets are disabled by default to minimize
  performance penalty if unused. Set to `true` to enable.
- `ext_opts`: Additional options passed to extmarks. Can be used to add
  passive/active highlight on a per-node-basis (more info in `DOC.md`)
- `parser_nested_assembler`: Override the default behavior of inserting a
  `choiceNode` containing the nested snippet and an empty `insertNode` for
  nested placeholders (`"${1: ${2: this is nested}}"`). For an example
  (behavior more similar to VSCode), check
  [here](https://github.com/L3MON4D3/LuaSnip/wiki/Nice-Configs#imitate-vscodes-behaviour-for-nested-placeholders)
- `ft_func`: Source of possible filetypes for snippets. Defaults to a function,
  which returns `vim.split(vim.bo.filetype, ".", true)`, but check
  [filetype_functions](lua/luasnip/extras/filetype_functions.lua) or the
  [Extras-Filetype-Functions](#filetype-functions)-section for more options.
- `load_ft_func`: Function to determine which filetypes belong to a given
  buffer (used for `lazy_loading`). `fn(bufnr) -> filetypes (string[])`. Again,
  there are some examples in
  [filetype_functions](lua/luasnip/extras/filetype_functions.lua).
- `snip_env`: The best way to author snippets in Lua involves the
  `lua-loader` (see [Loaders-Lua](#lua)).
  Unfortunately, this requires that snippets are defined in separate files,
  which means that common definitions like `s`, `i`, `sn`, `t`, `fmt`, ... have
  to be repeated in each of them, and that adding more customized functions to
  ease writing snippets also requires some setup.  
  `snip_env` can be used to insert variables into exactly the places where
  `lua-snippets` are defined (for now only the file loaded by the `lua-loader`).  
  Setting `snip_env` to `{ some_global = "a value" }` will add (amongst the
  defaults stated at the beginning of this documentation) the global variable
  `some_global` while evaluating these files.  
  There are special keys which, when set in `snip_env` change the behavior of
  this option, and are not passed through to the `lua-files`:
  * `__snip_env_behaviour`, string: either `"set"` or `"extend"` (default
    `"extend"`)  
    If this is `"extend"`, the variables defined in `snip_env` will complement (and
    override) the defaults. If this is not desired, `"set"` will not include the
    defaults, but only the variables set here.

- `loaders_store_source`, boolean, whether loaders should store the source of
  the loaded snippets.  
  Enabling this means that the definition of any snippet can be jumped to via
  [Extras-Snippet-Location](#snippet-location), but also entails slightly
  increased memory consumption (and load-time, but it's not really noticeable).

# Troubleshooting

## Adding Snippets

<a id="troubleshooting-adding-snippets-loaders"></a>

### Loaders

* **Filetypes**. LuaSnip uses `all` as the global filetype. As most snippet
  collections don't explicitly target LuaSnip, they may not provide global
  snippets for this filetype, but another, like `_` (`honza/vim-snippets`).
  In these cases, it's necessary to extend LuaSnip's global filetype with
  the collection's global filetype:
  ```lua
  ls.filetype_extend("all", { "_" })
  ```

  In general, if some snippets don't show up when loading a collection, a good
  first step is checking the filetype LuaSnip is actually looking into (print
  them for the current buffer via
  `:lua print(vim.inspect(require("luasnip").get_snippet_filetypes()))`),
  against the one the missing snippet is provided for (in the collection).  
  If there is indeed a mismatch, `filetype_extend` can be used to also search
  the collection's filetype:
  ```lua
  ls.filetype_extend("<luasnip-filetype>", { "<collection-filetype>" })
  ```

* **Non-default `ft_func` loading**. As we only load `lazy_load`ed snippets on
  some events, `lazy_load` will probably not play nice when a non-default
  `ft_func` is used: if it depends on e.g. the cursor position, only the
  filetypes for the cursor position when the `lazy_load` events are triggered
  will be loaded. Check [Extras-Filetype-Function](#filetype-functions)'s
  `extend_load_ft` for a solution.

### General

* **Snippets sharing triggers**. If multiple snippets could be triggered at
  the current buffer-position, the snippet that was defined first in one's
  configuration will be expanded first. As a small, real-world LaTeX math
  example, given the following two snippets with triggers `.ov` and `ov`:
  
  ```lua
  postfix( -- Insert over-line command to text via post-fix
      { trig = ".ov", snippetType = "autosnippet" },
      {
          f(function(_, parent)
              return "\\overline{" .. parent.snippet.env.POSTFIX_MATCH .. "}"
          end, {}),
      }
  ),
  s( -- Insert over-line command
      { trig = "ov", snippetType="autosnippet" },
      fmt(
          [[\overline{<>}]],
          { i(1) },
          { delimiters = "<>" }
      )
  ),
  ```
  
  If one types `x` followed by `.ov`, the postfix snippet expands producing
  `\overline{x}`. However, if the `postfix` snippet above is defined *after*
  the normal snippet `s`, then the same key press sequence produces
  `x.\overline{}`.
  This behavior can be overridden by explicitly providing a priority to
  such snippets. For example, in the above code, if the `postfix` snippet
  was defined after the normal snippet `s`, then adding `priority=1001` to the
  `postfix` snippet will cause it to expand as if it were defined before
  the normal snippet `s`. Snippet `priority` is discussed in the
   [Snippets section](#snippets) of the documentation.

# API

`require("luasnip")`:

#### `get_active_snip(): LuaSnip.Snippet?`

Get the currently active snippet.  

This function returns:

* `LuaSnip.Snippet?` The active snippet if one exists, or `nil`.

#### `get_snippets(ft?, opts?): (LuaSnip.Snippet[]|{ [string]: LuaSnip.Snippet[] })`

Retrieve snippets from luasnip.

* `ft?: string?` Filetype, if not given returns snippets for all filetypes.
* `opts?: LuaSnip.Opts.GetSnippets?` Optional arguments.  
  Valid keys are:

  * `type?: ("snippets"|"autosnippets")?` Whether to get snippets or autosnippets. Defaults to
    "snippets".

This function returns:

* `(LuaSnip.Snippet[]|{ [string]: LuaSnip.Snippet[] })` Flat array when `ft` is non-nil, otherwise a
  table mapping filetypes to snippets.

#### `available(snip_info?): { [string]: T[] }`

Retrieve information about snippets available in the current file/at the current position (in case
treesitter-based filetypes are enabled).

* `snip_info?: fun(LuaSnip.Snippet) -> T?` Optionally pass a function that, given a snippet, returns
  the data that is returned by this function in the snippets' stead. By default, this function is
  ```lua
  function(snip)
      return {
          name = snip.name,
          trigger = snip.trigger,
          description = snip.description,
          wordTrig = snip.wordTrig and true or false,
          regTrig = snip.regTrig and true or false,
      }
  end
  ```

This function returns:

* `{ [string]: T[] }` Table mapping filetypes to list of data returned by snip_info function.

#### `unlink_current()`

Removes the current snippet from the jumplist (useful if LuaSnip fails to automatically detect e.g.
deletion of a snippet) and sets the current node behind the snippet, or, if not possible, before it.

#### `jump(dir): boolean`

Jump forwards or backwards

* `dir: (1|-1)` Jump forward for 1, backward for -1.

This function returns:

* `boolean` `true` if a jump was performed, `false` otherwise.

#### `jump_destination(dir): LuaSnip.Node`

Find the node the next jump will end up at. This will not work always, because we will not update
the node before jumping, so if the jump would e.g. insert a new node between this node and its
pre-update jump target, this would not be registered. Thus, it currently only works for simple
cases.

* `dir: (1|-1)` `1`: find the next node, `-1`: find the previous node.

This function returns:

* `LuaSnip.Node` The destination node.

#### `jumpable(dir): boolean`

Return whether jumping forwards or backwards will actually jump, or if there is no node in that
direction.

* `dir: (1|-1)` `1` forward, `-1` backward.

#### `expandable(): boolean`

Return whether there is an expandable snippet at the current cursor position. Does not consider
autosnippets since those would already be expanded at this point.

#### `expand_or_jumpable(): boolean`

Return whether it's possible to expand a snippet at the current cursor-position, or whether it's
possible to jump forward from the current node.

#### `in_snippet(): boolean`

Determine whether the cursor is within a snippet.

#### `expand_or_locally_jumpable(): boolean`

Return whether a snippet can be expanded at the current cursor position, or whether the cursor is
inside a snippet and the current node can be jumped forward from.

#### `locally_jumpable(dir): boolean`

Return whether the cursor is inside a snippet and the current node can be jumped forward from.

* `dir: (1|-1)` Test jumping forwards/backwards.

#### `snip_expand(snippet, opts?): LuaSnip.ExpandedSnippet`

Expand a snippet in the current buffer.

* `snippet: LuaSnip.Snippet` The snippet.
* `opts?: LuaSnip.Opts.SnipExpand?` Optional additional arguments.  
  Valid keys are:

  * `clear_region?: LuaSnip.BufferRegion?` A region of text to clear after populating env-variables,
    but before jumping into `snip`. If `nil`, no clearing is performed. Being able to remove text at
    this point is useful as clearing before calling this function would populate `TM_CURRENT_LINE`
    and `TM_CURRENT_WORD` with wrong values (they would miss the snippet trigger). The actual values
    used for clearing are `region.from` and `region.to`, both (0,0)-indexed byte-positions in the
    buffer.
  * `expand_params?: LuaSnip.Opts.SnipExpandExpandParams?` Override various fields of the expanded
    snippet. Don't override anything by default. This is useful for manually expanding snippets
    where the trigger passed via `trig` is not the text triggering the snippet, or those which
    expect `captures` (basically, snippets with a non-plaintext `trigEngine`).

    One Example:
    ```lua
    snip_expand(snip, {
        trigger = "override_trigger",
        captures = {"first capture", "second capture"},
        env_override = { this_key = "some value", other_key = {"multiple", "lines"}, TM_FILENAME = "some_other_filename.lua" }
    })
    ```

    Valid keys are:
    * `trigger?: string?` What to set as the expanded snippets' trigger (Defaults to
      `snip.trigger`).
    * `captures?: string[]?` Set as the expanded snippets' captures (Defaults to `{}`).
    * `env_override?: { [string]: string }?` Set or override environment variables of the expanded
      snippet (Defaults to `{}`).
  * `pos?: (integer,integer)?` Position at which the snippet should be inserted. Pass as
    `(row,col)`, both 0-based, the `col` given in bytes.
  * `indent?: boolean?` Whether to prepend the current lines' indent to all lines of the snippet.
    (Defaults to `true`) Turning this off is a good idea when a LSP server already takes indents
    into consideration. In such cases, LuaSnip should not add additional indents. If you are using
    `nvim-cmp`, this could be used as follows:
    ```lua
    require("cmp").setup {
        snippet = {
            expand = function(args)
                local indent_nodes = true
                if vim.api.nvim_get_option_value("filetype", { buf = 0 }) == "dart" then
                    indent_nodes = false
                end
                require("luasnip").lsp_expand(args.body, {
                    indent = indent_nodes,
                })
            end,
        },
    }
    ```
  * `jump_into_func?: fun(snip: LuaSnip.Snippet) -> LuaSnip.Node?`

This function returns:

* `LuaSnip.ExpandedSnippet` The snippet that was inserted into the buffer.

#### `expand(opts?): boolean`

Find a snippet whose trigger matches the text before the cursor and expand it.

* `opts?: LuaSnip.Opts.Expand?` Subset of opts accepted by `snip_expand`.  
  Valid keys are:

  * `jump_into_func?: fun(snip: LuaSnip.Snippet) -> LuaSnip.Node?`

This function returns:

* `boolean` Whether a snippet was expanded.

#### `expand_auto()`

Find an autosnippet matching the text at the cursor-position and expand it.

#### `expand_repeat()`

Repeat the last performed `snip_expand`. Useful for dot-repeat.

#### `expand_or_jump(): boolean`

Expand at the cursor, or jump forward.  

This function returns:

* `boolean` Whether an action was performed.

#### `lsp_expand(body, opts?)`

Expand a snippet specified in lsp-style.

* `body: string` A string specifying a lsp-snippet, e.g. `"[${1:text}](${2:url})"`
* `opts?: LuaSnip.Opts.SnipExpand?` Optional args passed through to `snip_expand`.

#### `choice_active(): boolean`

Return whether the current node is inside a choiceNode.

#### `change_choice(val)`

Change the currently active choice.

* `val: (1|-1)` Move one choice forward or backward.

#### `set_choice(choice_indx)`

Set the currently active choice.

* `choice_indx: integer` Index of the choice to switch to.

#### `get_current_choices(): string[]`

Get a string-representation of all the current choiceNode's choices.  

This function returns:

* `string[]` \n-concatenated lines of every choice.

#### `active_update_dependents()`

Update all nodes that depend on the currently-active node.

#### `store_snippet_docstrings(snippet_table)`

Generate and store the docstrings for a list of snippets as generated by `get_snippets()`. The
docstrings are stored at `stdpath("cache") .. "/luasnip/docstrings.json"`, are indexed by their
trigger, and should be updated once any snippet changes.

* `snippet_table: { [string]: LuaSnip.Snippet[] }` A table mapping some keys to lists of snippets
  (keys are most likely filetypes).

#### `load_snippet_docstrings(snippet_table)`

Provide all passed snippets with a previously-stored (via `store_snippet_docstrings`) docstring.
This prevents a somewhat costly computation which is performed whenever a snippets' docstring is
first retrieved, but may cause larger delays when `snippet_table` contains many of snippets. Utilize
this function by calling `ls.store_snippet_docstrings(ls.get_snippets())` whenever snippets are
modified, and `ls.load_snippet_docstrings(ls.get_snippets())` on startup.

* `snippet_table: { [string]: LuaSnip.Snippet[] }` List of snippets, should contain the same keys
  (filetypes) as the table that was passed to `store_snippet_docstrings`. Again, most likely the
  result of `get_snippets`.

#### `unlink_current_if_deleted()`

Checks whether (part of) the current snippet's text was deleted, and removes it from the jumplist if
it was (it cannot be jumped back into).

#### `exit_out_of_region(node)`

Checks whether the cursor is still within the range of the root-snippet `node` belongs to. If yes,
no change occurs; if no, the root-snippet is exited and its `i(0)` will be the new active node. If a
jump causes an error (happens mostly because the text of a snippet was deleted), the snippet is
removed from the jumplist and the current node set to the end/beginning of the next/previous
snippet.

* `node: LuaSnip.Node`

#### `filetype_extend(ft, extend_ft)`

Add `extend_ft` filetype to inherit its snippets from `ft`.

Example:
```lua
ls.filetype_extend("sh", {"zsh"})
ls.filetype_extend("sh", {"bash"})
```
This makes all `sh` snippets available in `sh`/`zsh`/`bash` buffers.

* `ft: string`
* `extend_ft: string[]`

#### `filetype_set(ft, fts)`

Set `fts` filetypes as inheriting their snippets from `ft`.

Example:
```lua
ls.filetype_set("sh", {"sh", "zsh", "bash"})
```
This makes all `sh` snippets available in `sh`/`zsh`/`bash` buffers.

* `ft: string`
* `fts: string[]`

#### `cleanup()`

Clear all loaded snippets. Also sends the `User LuasnipCleanup` autocommand, so plugins that depend
on luasnip's snippet-state can clean up their now-outdated state.

#### `refresh_notify(ft)`

Trigger the `User LuasnipSnippetsAdded` autocommand that signifies to other plugins that a filetype
has received new snippets.

* `ft: string` The filetype that has new snippets. Code that listens to this event can retrieve this
  filetype from `require("luasnip").session.latest_load_ft`.

#### `setup_snip_env()`

Injects the fields defined in `snip_env`, in `setup`, into the callers global environment.

This means that variables like `s`, `sn`, `i`, `t`, ... (by default) work, and are useful for
quickly testing snippets in a buffer:
```lua
local ls = require("luasnip")
ls.setup_snip_env()

ls.add_snippets("all", {
    s("choicetest", {
        t":", c(1, {
            t("asdf", {node_ext_opts = {active = { virt_text = {{"asdf", "Comment"}} }}}),
            t("qwer", {node_ext_opts = {active = { virt_text = {{"qwer", "Comment"}} }}}),
        })
    })
}, { key = "3d9cd211-c8df-4270-915e-bf48a0be8a79" })
```
where the `key` makes it easy to reload the snippets on changes, since the previously registered
snippets will be replaced when the buffer is re-sourced.

#### `get_snip_env(): table`

Return the currently active snip_env.

#### `get_id_snippet(id): LuaSnip.Snippet`

Get the snippet corresponding to some id.

* `id: LuaSnip.SnippetID`

#### `add_snippets(ft?, snippets, opts?)`

Add snippets to luasnip's snippet-collection.

NOTE: Calls `refresh_notify` as needed if enabled via `opts.refresh_notify`.

* `ft?: string?` The filetype to add the snippets to, or nil if the filetype is specified in
  `snippets`.
* `snippets: (LuaSnip.Addable[]|{ [string]: LuaSnip.Addable[] })` If `ft` is nil a table mapping a
  filetype to a list of snippets, otherwise a flat table of snippets. `LuaSnip.Addable` are objects
  created by e.g. the functions `s`, `ms`, or `sp`.
* `opts?: LuaSnip.Opts.AddSnippets?` Optional arguments.

#### `clean_invalidated(opts?)`

Clean invalidated snippets from internal snippet storage. Invalidated snippets are still stored; it
might be useful to actually remove them as they still have to be iterated during expansion.

* `opts?: LuaSnip.Opts.CleanInvalidated?` Additional, optional arguments.  
  Valid keys are:

  * `inv_limit?: integer?` If set, invalidated snippets are only cleared if their number exceeds
    `inv_limit`.

#### `activate_node(opts?)`

Lookup a node by position and activate (ie. jump into) it.

* `opts?: LuaSnip.Opts.ActivateNode?` Additional, optional arguments.  
  Valid keys are:

  * `strict?: boolean?` Only activate nodes one could usually jump to. (Defaults to false)
  * `select?: boolean?` Whether to select the entire node, or leave the cursor at the position it is
    currently at. (Defaults to true)
  * `pos?: LuaSnip.BytecolBufferPosition?` Where to look for the node. (Defaults to the position of
    the cursor)

Not covered in this section are the various node-constructors exposed by
the module, their usage is shown either previously in this file or in
`Examples/snippets.lua` (in the repository).
