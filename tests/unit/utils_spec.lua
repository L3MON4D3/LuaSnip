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
	local get_parent = require("luasnip.util.path").parent
	local function assert_parents(examples)
		for _, example in ipairs(examples) do
			assert.are.same(example.expect, get_parent(example.path))
		end
	end

	if jit and jit.os:lower() == "windows" then
		describe("handles windows paths", function()
			local examples = {
				{
					path = [[C:\Users\username\AppData\Local\nvim-data\log]],
					expect = [[C:\Users\username\AppData\Local\nvim-data\]],
				},
				{
					path = [[C:/Users/username/AppData/Local/nvim-data/log]],
					expect = [[C:/Users/username/AppData/Local/nvim-data/]],
				},
				{
					path = [[D:\Projects\project_folder\source_code.py]],
					expect = [[D:\Projects\project_folder\]],
				},
				{
					path = [[D:/Projects/project_folder/source_code.py]],
					expect = [[D:/Projects/project_folder/]],
				},
				{ path = [[E:\Music\\\\]], expect = [[E:\]] },
				{ path = [[E:/Music////]], expect = [[E:/]] },
				{ path = [[E:\\Music\\\\]], expect = [[E:\\]] },
				{ path = [[E://Music////]], expect = [[E://]] },
				{ path = [[F:\]], expect = nil },
				{ path = [[F:\\]], expect = nil },
				{ path = [[F:/]], expect = nil },
				{ path = [[F://]], expect = nil },
			}

			assert_parents(examples)
		end)
	elseif jit and jit.os:lower() == "linux" then
		describe("handles linux paths", function()
			local examples = {
				{
					path = [[/home/usuario/documents/archivo.txt]],
					expect = [[/home/usuario/documents/]],
				},
				{
					path = [[/var/www/html////index.html]],
					expect = [[/var/www/html////]],
				},
				{
					path = [[/mnt/backup/backup_file.tar.gz]],
					expect = [[/mnt/backup/]],
				},
				{
					path = [[/mnt/]],
					expect = [[/]],
				},
				{
					path = [[/mnt////]],
					expect = [[/]],
				},
				{
					path = [[/project/\backslash\is\legal\in\linux\filename.txt]],
					expect = [[/project/]],
				},
				{
					path = [[/\\\\]],
					expect = [[/]],
				},
				{
					path = [[/\\\\////]],
					expect = [[/]],
				},
				{ path = [[/]], expect = nil },
			}

			assert_parents(examples)
		end)
	elseif jit and jit.os:lower() == "osx" then
		describe("handles macos paths", function()
			local examples = {
				{
					path = [[/Users/Usuario/Documents/archivo.txt]],
					expect = [[/Users/Usuario/Documents/]],
				},
				{
					path = [[/Applications/App.app/Contents/MacOS/app_executable]],
					expect = [[/Applications/App.app/Contents/MacOS/]],
				},
				{
					path = [[/Volumes/ExternalDrive/Data/file.xlsx]],
					expect = [[/Volumes/ExternalDrive/Data/]],
				},
				{ path = [[/Volumes/]], expect = [[/]] },
				{ path = [[/Volumes////]], expect = [[/]] },
				{
					path = [[/project/\backslash\is\legal\in\macos\filename.txt]],
					expect = [[/project/]],
				},
				{
					path = [[/\\\\]],
					expect = [[/]],
				},
				{
					path = [[/\\\\////]],
					expect = [[/]],
				},
				{ path = [[/]], expect = nil },
			}

			assert_parents(examples)
		end)
	end
end)
