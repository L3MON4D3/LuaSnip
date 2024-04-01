return {
	check = function()
		vim.health.start("luasnip")
		local jsregexp = require("luasnip.util.jsregexp")
		if jsregexp then
			vim.health.ok("jsregexp is installed")
		else
			vim.health.warn([[
            For Variable/Placeholder-transformations, luasnip requires
            the jsregexp library. See `:h luasnip-lsp-snippets-transformations` for advice
        ]])
		end
	end,
}
