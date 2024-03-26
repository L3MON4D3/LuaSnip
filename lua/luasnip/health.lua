return {
	check = function()
		vim.health.start("luasnip")
		vim.health.info()
		local jsregexp = require("luasnip.util.jsregexp")
		if jsregexp then
			vim.health.ok("jsregexp is installed")
		else
			vim.health.error([[
            For Variable/Placeholder-transformations, luasnip requires
            the jsregexp library. See `:h luasnip-transformations` for advice
        ]])
		end
	end,
}
