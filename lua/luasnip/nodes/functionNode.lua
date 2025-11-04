local Node = require("luasnip.nodes.node").Node
local util = require("luasnip.util.util")
local node_util = require("luasnip.nodes.util")
local types = require("luasnip.util.types")
local tNode = require("luasnip.nodes.textNode").textNode
local extend_decorator = require("luasnip.util.extend_decorator")
local key_indexer = require("luasnip.nodes.key_indexer")
local opt_args = require("luasnip.nodes.optional_arg")
local snippet_string = require("luasnip.nodes.util.snippet_string")

---@alias LuaSnip.FunctionNode.Fn fun(args: (string[])[], parent: LuaSnip.Snippet | LuaSnip.SnippetNode, ...: table): string|string[]

---@class LuaSnip.FunctionNode: LuaSnip.Node
---@field fn LuaSnip.FunctionNode.Fn
---@field user_args any[] Additional args that will be passed to `fn`
---@field args LuaSnip.NodeRef[]
---@field args_absolute LuaSnip.NormalizedNodeRef[]
---@field last_args ((string[])[])?
local FunctionNode = Node:new()

---@class LuaSnip.Opts.FunctionNode: LuaSnip.Opts.Node
---@field user_args? any[] Additional args that will be passed to `fn` as
---  `user_arg1`-`user_argn`.
---
---  These make it easier to reuse similar functions, for example a functionNode
---  that wraps some text in different delimiters (`()`, `[]`, ...).
---  ```lua
---  local function reused_func(_,_, user_arg1)
---      return user_arg1
---  end
---
---  s("trig", {
---      f(reused_func, {}, {
---          user_args = {"text"}
---      }),
---      f(reused_func, {}, {
---          user_args = {"different text"}
---      }),
---  })
---  ```

--- Function Nodes insert text based on the content of other nodes using a
--- user-defined function:
---
--- ```lua
--- local function fn(
---   args,     -- text from i(2) in this example i.e. { { "456" } }
---   parent,   -- parent snippet or parent node
---   user_args -- user_args from opts.user_args
--- )
---    return '[' .. args[1][1] .. user_args .. ']'
--- end
---
--- s("trig", {
---   i(1), t '<-i(1) ',
---   f(fn,  -- callback (args, parent, user_args) -> string
---     {2}, -- node indice(s) whose text is passed to fn, i.e. i(2)
---     { user_args = { "user_args_value" }} -- opts
---   ),
---   t ' i(2)->', i(2), t '<-i(2) i(0)->', i(0)
--- })
--- ```
---
---@param fn LuaSnip.FunctionNode.Fn
---
---  - `argnode_text`: The text currently contained in the argnodes
---    (e.g. `{{line1}, {line1, line2}}`).
---    The snippet indent will be removed from all lines following the first.
---
---  - `parent`: The immediate parent of the `functionNode`. It is included here
---    as it allows easy access to some information that could be useful in
---    functionNodes (see [Snippets-Data](#data) for some examples).
---
---    Many snippets access the surrounding snippet just as `parent`, but if the
---    `functionNode` is nested within a `snippetNode`, the immediate parent is
---    a `snippetNode`, not the surrounding snippet (only the surrounding
---    snippet contains data like `env` or `captures`).
---
---  - `user_args`: The `user_args` passed in `opts`. Note that there may be
---    multiple `user_args` (e.g. `user_args1, ..., user_argsn`).
---
---  The function shall return a string, which will be inserted as is, or a
---  table of strings for multiline strings, where all lines following the first
---  will be prefixed with the snippets' indentation.
---
---@param argsnode_refs? LuaSnip.NodeRef[]|LuaSnip.NodeRef
---  [Node References](#node-reference) to the nodes the functionNode depends
---  on.
---  Changing any of these will trigger a re-evaluation of `fn`, and insertion of
---  the updated text.
---  If no node reference is passed, the `functionNode` is evaluated once upon
---  expansion.
---
---@param node_opts? LuaSnip.Opts.FunctionNode
---@return LuaSnip.FunctionNode
local function F(fn, argsnode_refs, node_opts)
	node_opts = node_opts or {}

	local node = FunctionNode:new({
		fn = fn,
		args = node_util.wrap_args(argsnode_refs or {}),
		args_absolute = {},
		type = types.functionNode,
		mark = nil,
		user_args = node_opts.user_args or {},
	}, node_opts)
	---@cast node LuaSnip.FunctionNode
	return node
end
extend_decorator.register(F, { arg_indx = 3 })

FunctionNode.input_enter = tNode.input_enter

function FunctionNode:get_static_text()
	-- static_text will already have been generated, if possible.
	-- If it isn't generated, prevent errors by just setting it to empty text.
	if not self.static_text then
		self.static_text = { "" }
	end
	return self.static_text
end

-- function-text will not stand out in any way in docstring.
FunctionNode.get_docstring = FunctionNode.get_static_text

function FunctionNode:update()
	local args = node_util.str_args(self:get_args())
	-- skip this update if
	-- - not all nodes are available.
	-- - the args haven't changed.
	if not args or vim.deep_equal(args, self.last_args) then
		return
	end

	if not self.parent.snippet:extmarks_valid() then
		error("Refusing to update inside a snippet with invalid extmarks")
	end

	self.last_args = args
	local text =
		util.to_string_table(self.fn(args, self.parent, unpack(self.user_args)))
	if vim.bo.expandtab then
		util.expand_tabs(text, util.tab_width(), #self.parent.indentstr)
	end

	-- don't expand tabs in parent.indentstr, use it as-is.
	self:set_text_raw(util.indent(text, self.parent.indentstr))
	self.static_text = text

	-- assume that functionNode can't have a parent as its dependent, there is
	-- no use for that I think.
	self:update_dependents({ own = true, parents = true })
end

local update_errorstring = [[
Error while evaluating functionNode@%d for snippet '%s':
%s
 
:h luasnip-docstring for more info]]
function FunctionNode:update_static()
	local args = node_util.str_args(self:get_static_args())

	-- skip this update if
	-- - not all nodes are available.
	-- - the args haven't changed.
	if not args or vim.deep_equal(args, self.last_args) then
		return
	end
	-- should be okay to set last_args even if `fn` potentially fails, future
	-- updates will fail aswell, if not the `fn` also doesn't always work
	-- correctly in normal expansion.
	self.last_args = args
	local ok, static_text =
		pcall(self.fn, args, self.parent, unpack(self.user_args))
	if not ok then
		print(
			update_errorstring:format(
				self.indx,
				self.parent.snippet.name,
				static_text
			)
		)
		static_text = { "" }
	end
	self.static_text =
		util.indent(util.to_string_table(static_text), self.parent.indentstr)
end

function FunctionNode:update_restore()
	local args = node_util.str_args(self:get_args())
	-- only if args still match.
	if self.static_text and vim.deep_equal(args, self.last_args) then
		self:set_text_raw(self.static_text)
	else
		self:update()
	end
end

-- FunctionNode's don't have static text, only set visibility.
function FunctionNode:put_initial(_)
	self.visible = true
end

function FunctionNode:indent(_) end

function FunctionNode:expand_tabs(_) end

function FunctionNode:make_args_absolute(position_so_far)
	self.args_absolute = {}
	node_util.make_args_absolute(self.args, position_so_far, self.args_absolute)
end

function FunctionNode:set_dependents()
	local dict = self.parent.snippet.dependents_dict
	local append_list =
		vim.list_extend({ "dependents" }, self.absolute_position)
	append_list[#append_list + 1] = "dependent"

	for _, arg in ipairs(self.args_absolute) do
		if opt_args.is_opt(arg) then
			arg = arg.ref
		end
		-- if arg is a luasnip-node, just insert it as the key.
		-- important!! rawget, because indexing absolute_indexer with some key
		-- appends the key.
		-- Maybe this is stupid??
		if rawget(arg, "type") ~= nil then
			dict:set(vim.list_extend({ arg }, append_list), self)
		elseif arg.absolute_insert_position then
			-- copy absolute_insert_position, list_extend mutates.
			dict:set(
				vim.list_extend(
					vim.deepcopy(arg.absolute_insert_position),
					append_list
				),
				self
			)
		elseif key_indexer.is_key(arg) then
			dict:set(vim.list_extend({ "key", arg.key }, append_list), self)
		end
	end
end

function FunctionNode:is_interactive()
	-- the function node is only evaluated once if it has no argnodes -> it's
	-- not interactive then.
	return #self.args ~= 0
end

return {
	F = F,
	FunctionNode = FunctionNode,
}
