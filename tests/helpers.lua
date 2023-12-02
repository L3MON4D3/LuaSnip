local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua
local exec = helpers.exec
local assert = require("luassert")

local M = {}

function M.jsregexp_it(it, name, fn)
	for _, version in ipairs({ "005", "006", "luasnip" }) do
		it(name .. " (jsregexp-" .. version .. ")", function()
			exec_lua(
				[[
				local version, jsregexp_005_path, jsregexp_path = ...
				if version ~= "luasnip" then
					if version == "005" then
						package.preload["jsregexp"] = package.loadlib(jsregexp_005_path .. "/jsregexp.so", "luaopen_jsregexp")

						if package.preload["jsregexp"]().compile_safe then
							error("wrong jsregexp-version loaded")
						end
					else
						package.preload["jsregexp.core"] = package.loadlib(jsregexp_path .. "/jsregexp.so", "luaopen_jsregexp_core")
						package.path = jsregexp_path .. "/?.lua;;"
						-- populate package now, before jsregexp-core-preload is overwritten in util/jsregexp.lua.
						-- also load it to check the version.
						local jsregexp = require("jsregexp")
						-- is actually 0.0.6.
						if not jsregexp.compile_safe then
							error("wrong jsregexp-version loaded")
						end
					end

					-- don't accidentially load luasnip-jsregexp with unknown version.
					local old_require = require
					require = function(modulename)
						if modulename == "luasnip-jsregexp" then
							error("Disabled by `prevent_jsregexp`")
						end
						return old_require(modulename)
					end
				else
					-- don't accidentially load regular jsregexp.
					local old_require = require
					require = function(modulename)
						if modulename == "jsregexp" then
							error("Disabled by `prevent_jsregexp`")
						end
						return old_require(modulename)
					end
				end
			]],
				version,
				os.getenv("JSREGEXP005_ABS_PATH"),
				os.getenv("JSREGEXP_ABS_PATH")
			)

			fn()
		end)
	end
end

function M.prevent_jsregexp()
	-- append default-path.
	exec_lua([[
		local old_require = require
		require = function(modulename)
			if modulename == "jsregexp" or modulename == "luasnip-jsregexp" then
				error("Disabled by `prevent_jsregexp`")
			end
			return old_require(modulename)
		end
	]])
end

function M.session_setup_luasnip(opts)
	opts = opts or {}
	local no_snip_globals = opts.no_snip_globals ~= nil and opts.no_snip_globals
		or false
	local setup_extend = opts.setup_extend ~= nil and opts.setup_extend or {}
	local setup_parsers
	if opts.setup_parsers ~= nil then
		setup_parsers = opts.setup_parsers
	else
		setup_parsers = false
	end
	-- nil or true.
	local hl_choiceNode = opts.hl_choiceNode

	-- stylua: ignore
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))
	helpers.exec(
		("source %s/plugin/luasnip.vim"):format(os.getenv("LUASNIP_SOURCE"))
	)
	helpers.exec(
		("luafile %s/plugin/luasnip.lua"):format(os.getenv("LUASNIP_SOURCE"))
	)

	if setup_parsers then
		-- adding the lua-parser, is either a nop or adds the parser on
		-- versions where it does not exist by default.
		exec_lua([[
			ts_lang_add =
				(vim.treesitter.language and vim.treesitter.language.add)
				and function(lang, path)
						vim.treesitter.language.add(lang, {path = path})
					end
				or vim.treesitter.require_language

			-- this is a nop on new versions of neovim, where the lua-parser is shipped by default.
			ts_lang_add("lua", os.getenv("LUASNIP_SOURCE") .. "/tests/parsers/lua.so")

			ts_lang_add("json", os.getenv("LUASNIP_SOURCE") .. "/tests/parsers/json.so")
			ts_lang_add("jsonc", os.getenv("LUASNIP_SOURCE") .. "/tests/parsers/jsonc.so")
		]])
	end

	helpers.exec_lua(
		[[
		local hl_choiceNode, setup_extend = ...

		-- MYVIMRC might not be set when nvim is loaded like this.
		vim.env.MYVIMRC = "/.vimrc"

		ls = require("luasnip")
		ls.setup(vim.tbl_extend("force", {
			store_selection_keys = "<Tab>"
		}, hl_choiceNode and {
			ext_opts = {
				[require("luasnip.util.types").choiceNode] = {
					active = {
						virt_text = {{"●", "ErrorMsg"}},
						priority = 0
					},
				}
			},
		} or {}, setup_extend))
	]],
		-- passing nil here means the argument-list is terminated, I think.
		-- Just pass false instead of nil/false.
		hl_choiceNode or false,
		setup_extend
	)

	if not no_snip_globals then
		helpers.exec_lua([[
			s = ls.s
			sn = ls.sn
			t = ls.t
			i = ls.i
			f = ls.f
			c = ls.c
			d = ls.d
			isn = require("luasnip.nodes.snippet").ISN
			l = require'luasnip.extras'.lambda
			dl = require'luasnip.extras'.dynamic_lambda
			rep = require'luasnip.extras'.rep
			r = ls.restore_node
			p = require("luasnip.extras").partial
			types = require("luasnip.util.types")
			events = require("luasnip.util.events")
			fmt = require("luasnip.extras.fmt").fmt
			fmta = require("luasnip.extras.fmt").fmta
			parse = ls.parser.parse_snippet
			n = require("luasnip.extras").nonempty
			m = require("luasnip.extras").match
			ai = require("luasnip.nodes.absolute_indexer")
			sp = require("luasnip.nodes.snippetProxy")
			pf = require("luasnip.extras.postfix").postfix
			k = require("luasnip.nodes.key_indexer").new_key
		]])
	end
end

function M.static_docstring_test(snip_str, static, docstring)
	assert.are.same(
		static,
		exec_lua("return " .. snip_str .. ":get_static_text()")
	)
	assert.are.same(
		docstring,
		exec_lua("return " .. snip_str .. ":get_docstring()")
	)
end
function M.lsp_static_test(snip_str, static)
	assert.are.same(
		static,
		exec_lua(
			'return ls.parser.parse_snippet("trig", '
				.. snip_str
				.. "):get_static_text()"
		)
	)
end

M.loaders = {
	["vscode(rtp)"] = function()
		exec(
			"set rtp+="
				.. os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/vscode-snippets"
		)
		exec_lua('require("luasnip.loaders.from_vscode").load()')
	end,
	["vscode(path)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_vscode").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
			)
		)
	end,
	["vscode(lazy)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_vscode").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE") .. "/tests/data/vscode-snippets"
			)
		)
	end,
	["vscode(standalone)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_vscode").load_standalone({path="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/vscode-standalone.code-snippets"
			)
		)
	end,

	["snipmate(rtp)"] = function()
		exec(
			"set rtp+="
				.. os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/snipmate-snippets"
		)
		exec_lua('require("luasnip.loaders.from_snipmate").load()')
	end,
	["snipmate(path)"] = function(dir)
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/"
					.. dir
			)
		)
	end,
	["snipmate(lazy)"] = function(dir)
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_snipmate").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/snipmate-snippets/"
					.. dir
			)
		)
	end,

	["lua(rtp)"] = function()
		exec(
			"set rtp+="
				.. os.getenv("LUASNIP_SOURCE")
				.. "/tests/data/lua-snippets"
		)
		exec_lua('require("luasnip.loaders.from_lua").load()')
	end,
	["lua(path)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets"
			)
		)
	end,
	["lua(lazy)"] = function()
		exec_lua(
			string.format(
				[[require("luasnip.loaders.from_lua").lazy_load({paths="%s"})]],
				os.getenv("LUASNIP_SOURCE")
					.. "/tests/data/lua-snippets/luasnippets"
			)
		)
	end,
}

function M.check_global_node_refs(test_name, resolve_map, fn)
	for _, index_strategy in ipairs({ "absolute_indexer", "key_indexer" }) do
		getfenv(2).it(("%s (%s)."):format(test_name, index_strategy), function()
			exec_lua(
				[[
				resolve_map, strategy = ...
				function _luasnip_test_resolve(key)
					if strategy == "absolute_indexer" then
						return ai(resolve_map[key][1])
					else
						return k(resolve_map[key][2])
					end
				end
			]],
				resolve_map,
				index_strategy
			)
			fn()
		end)
	end
end

local scratchdir_path = ("%s/tests/scratch"):format(os.getenv("LUASNIP_SOURCE"))
M.scratchdir_path = scratchdir_path

function M.scratch_prepare()
	-- clean (maybe a test was not able to clean up after itself) and re-create
	-- scratch-directory.
	os.execute(('rm -rf "%s"'):format(scratchdir_path))
	os.execute(('mkdir "%s"'):format(scratchdir_path))

	exec_lua(([[
		local function translate_callbacks(cbs)
			local cbs_new = {}

			for name, cb in pairs(cbs) do
				cbs_new[name] = function(full_path)
					-- +1 to start behind scratch-path, +1 to omit
					-- path-separator.
					cb(full_path:sub(%s + 2))
				end
			end

			return cbs_new
		end

		function scratch_tree_watcher(root_scratch_rel, depth, cbs, opts)
			return require("luasnip.loaders.fs_watchers").tree("%s/" .. root_scratch_rel, depth, translate_callbacks(cbs), opts)
		end

		function scratch_path_watcher(root_scratch_rel, cbs, opts)
			return require("luasnip.loaders.fs_watchers").path("%s/" .. root_scratch_rel, translate_callbacks(cbs), opts)
		end
	]]):format(#scratchdir_path, scratchdir_path, scratchdir_path))
end

function M.scratch_mkdir(scratch_rel)
	os.execute(('mkdir -p "%s/%s"'):format(scratchdir_path, scratch_rel))
end
function M.scratch_touch(scratch_rel)
	os.execute(('touch "%s/%s"'):format(scratchdir_path, scratch_rel))
end

function M.scratch_clear()
	os.execute(('rm -rf "%s"'):format(scratchdir_path))
end

function M.scratch_edit(scratch_rel)
	-- trigger BufWritePost.
	exec(("edit %s/%s"):format(scratchdir_path, scratch_rel))

	-- can replace with "write ++p" once we drop support for old versions.
	M.scratch_mkdir(scratch_rel:gsub("%/[^%/]+$", ""))
	exec(("write"):format(scratchdir_path, scratch_rel))
end

return M
