local ls_helpers = require("helpers")
local exec_lua = ls_helpers.exec_lua

describe("luasnip.util.str:dedent", function()
	ls_helpers.clear()
	ls_helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	local function check(test_name, input, output)
		it(test_name, function()
			assert.are.same(
				output,
				exec_lua(
					'return require("luasnip.util.str").dedent([['
						.. input
						.. "]])"
				)
			)
		end)
	end

	check("2 and 0", "   one", "one")
	check("0 and 2", "one\n  two", "one\n  two")
	check("2 and 1", "  one\n two", " one\ntwo")
	check("2 and 2", "  one\n  two", "one\ntwo")
end)

describe("luasnip.util.Path.parent", function()
	local function assert_parents(separator, examples)
		for _, example in ipairs(examples) do
			if example.expect then
				it(example.path, function()
					assert.are.same(
						example.expect,
						exec_lua(
							"__LUASNIP_TEST_SEP_OVERRIDE = [["
								.. separator
								.. "]] "
								.. 'return require("luasnip.util.path").parent([['
								.. separator
								.. "]])([["
								.. example.path
								.. "]])"
						)
					)
				end)
			else
				it(example.path .. " to be nil", function()
					assert.is_true(
						exec_lua(
							"__LUASNIP_TEST_SEP_OVERRIDE = [["
								.. separator
								.. "]] "
								.. 'return require("luasnip.util.path").parent([['
								.. separator
								.. "]])([["
								.. example.path
								.. "]]) == nil"
						)
					)
				end)
			end
		end
	end

	describe("backslash as the path separator", function()
		local examples = {
			{
				path = [[C:\Users\username\AppData\Local\nvim-data\log]],
				expect = [[C:\Users\username\AppData\Local\nvim-data]],
			},
			{
				path = [[C:/Users/username/AppData/Local/nvim-data/log]],
				expect = [[C:/Users/username/AppData/Local/nvim-data]],
			},
			{
				path = [[D:\Projects\project_folder\source_code.py]],
				expect = [[D:\Projects\project_folder]],
			},
			{
				path = [[D:/Projects/project_folder/source_code.py]],
				expect = [[D:/Projects/project_folder]],
			},
			{ path = [[E:\Music\\\\]], expect = nil },
			{ path = [[E:/Music////]], expect = nil },
			{ path = [[E:\\Music\\\\]], expect = nil },
			{ path = [[E://Music////]], expect = nil },
			{ path = [[F:\]], expect = nil },
			{ path = [[F:\\]], expect = nil },
			{ path = [[F:/]], expect = nil },
			{ path = [[F://]], expect = nil },
		}

		assert_parents("\\", examples)
	end)

	describe("forward slash as the path separator", function()
		local examples = {
			{
				path = [[/home/usuario/documents/archivo.txt]],
				expect = [[/home/usuario/documents]],
			},
			{
				path = [[/var/www/html////index.html]],
				expect = [[/var/www/html]],
			},
			{
				path = [[/mnt/backup/backup_file.tar.gz]],
				expect = [[/mnt/backup]],
			},
			{
				path = [[/mnt/]],
				expect = nil,
			},
			{
				path = [[/mnt////]],
				expect = nil,
			},
			{
				path = [[/project/\backslash\is\legal\in\linux\filename.txt]],
				expect = [[/project]],
			},
			{
				path = [[/\\\\]],
				expect = "",
			},
			{
				path = [[/\\\\////]],
				expect = nil,
			},
			{ path = [[/]], expect = nil },
		}

		assert_parents("/", examples)
	end)
end)
