local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec
local Screen = require("test.functional.ui.screen")

describe("treesitter-postfix", function()
	local screen

	local function setup(...)
		ls_helpers.clear()

		ls_helpers.session_setup_luasnip(...)
		screen = ls_helpers.new_screen(50, 8)
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end
	before_each(function()
		setup({ setup_parsers = true })
	end)

	after_each(function()
		screen:detach()
	end)

	for _, reparse_mode in ipairs({ [["live"]], [["copy"]], [[nil]] }) do
		it(("Default-case works [%s]"):format(reparse_mode), function()
			if
				exec_lua(
					[[return vim.version().major == 0 and vim.version().minor < 9]]
				)
			then
				-- make sure we throw a readable error.
				local err = exec_lua(
					[[return {pcall(require, "luasnip.extras.treesitter_postfix")}]]
				)[2]
				assert(
					err:match(
						"treesitter_postfix does not support neovim < 0.9"
					)
				)
				return
			end
			-- overrides snippet from previous iteration.
			exec_lua(([=[
				local ts_post = require("luasnip.extras.treesitter_postfix").treesitter_postfix

				ls.add_snippets("all", {
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
						reparseMode = %s,
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
				}, {key = "asdf"})
			]=]):format(reparse_mode))

			exec("set ft=lua")
			feed("ifunction add(a, b)\n\treturn a + b\nend")
			feed(".var")
			screen:expect({
				grid = [[
				function add(a, b)                                |
				        return a + b                              |
				end.var^                                           |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
				local add = function(a, b)                        |
				        return a + b                              |
				end^                                               |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end)
		it(("Builtin functions work [%s]"):format(reparse_mode), function()
			if
				exec_lua(
					[[return vim.version().major == 0 and vim.version().minor < 9]]
				)
			then
				return
			end

			-- overrides snippet from previous iteration.
			exec_lua(([=[
				local ts_post = require("luasnip.extras.treesitter_postfix").treesitter_postfix
				local postfix_builtin = require("luasnip.extras.treesitter_postfix").builtin

				local l_str = {}
				l.import("string", l_str)

				ls.add_snippets("all", {
					ts_post({
						matchTSNode = postfix_builtin.tsnode_matcher.find_topmost_types({
							"identifier",
						}),
						trig = ".mv",
						reparseMode = %s
					}, {
						l(l_str.format("std::move(%s)", l.LS_TSMATCH))
					})
				}, {key = "asdf"})
			]=]):format(reparse_mode, "%s"))

			exec("set ft=c")
			feed("iint main() {\n\tint a = 0;\n\tint b = a;\n}<Esc>k$i")
			feed(".mv")
			screen:expect({
				grid = [[
				int main() {                                      |
				        int a = 0;                                |
				        int b = a.mv^;                             |
				}                                                 |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
			exec_lua("ls.expand()")
			screen:expect({
				grid = [[
				int main() {                                      |
				        int a = 0;                                |
				        int b = std::move(a)^;                     |
				}                                                 |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})
		end)
	end
end)
