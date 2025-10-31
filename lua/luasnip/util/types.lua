---@enum LuaSnip.NodeType
local NodeType = {
	textNode = 1,
	insertNode = 2,
	functionNode = 3,
	snippetNode = 4,
	choiceNode = 5,
	dynamicNode = 6,
	snippet = 7,
	exitNode = 8,
	restoreNode = 9,
}

local M = setmetatable({}, { __index = NodeType })

local refs = {
	{ value = NodeType.textNode, name = "textNode", pascal_name = "TextNode" },
	{
		value = NodeType.insertNode,
		name = "insertNode",
		pascal_name = "InsertNode",
	},
	{
		value = NodeType.functionNode,
		name = "functionNode",
		pascal_name = "FunctionNode",
	},
	{
		value = NodeType.snippetNode,
		name = "snippetNode",
		pascal_name = "SnippetNode",
	},
	{
		value = NodeType.choiceNode,
		name = "choiceNode",
		pascal_name = "ChoiceNode",
	},
	{
		value = NodeType.dynamicNode,
		name = "dynamicNode",
		pascal_name = "DynamicNode",
	},
	{ value = NodeType.snippet, name = "snippet", pascal_name = "Snippet" },
	{ value = NodeType.exitNode, name = "exitNode", pascal_name = "ExitNode" },
	{
		value = NodeType.restoreNode,
		name = "restoreNode",
		pascal_name = "RestoreNode",
	},
}

---@type LuaSnip.NodeType[]
M.node_types = {}
---@type string[]
M.names = {}
---@type string[]
M.names_pascal_case = {}

for _, ref in ipairs(refs) do
	table.insert(M.node_types, ref.value)
	table.insert(M.names, ref.name)
	table.insert(M.names_pascal_case, ref.pascal_name)
end

return M
