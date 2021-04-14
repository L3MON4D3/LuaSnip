local FunctionNode = require'luasnip.nodes.node'.Node:new()

local function F(fn, args, ...)
	return FunctionNode:new{fn = fn, args = args, type = 2,  markers = {},user_args = {...}}
end

function FunctionNode:get_args()
	local args = {}
	for i, node in ipairs(self.args) do
		args[i] = node:get_text()
	end
	args[#args+1] = self.parent
	return args
end

function FunctionNode:update()
	self.parent:set_text(self, self.fn(self:get_args(), unpack(self.user_args)))
end

return {
	F = F
}
