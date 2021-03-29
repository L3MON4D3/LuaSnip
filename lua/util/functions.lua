return {
	-- supported lsp-vars.
	lsp = {
		TM_CURRENT_LINE = true,
		TM_CURRENT_WORD = true,
		TM_LINE_INDEX = true,
		TM_LINE_NUMBER = true,
		TM_FILENAME = true,
		TM_FILENAME_BASE = true,
		TM_DIRECTORY = true,
		TM_FILEPATH = true,
		var = function(_, node, text) return {node.parent.env[text]} end
	},
	copy = function(args) return args[1] end
}
