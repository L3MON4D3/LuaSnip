local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua
local exec = helpers.exec
local ls_helpers = require("helpers")

describe("luasnip.util.extend_decorator", function()
	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()
		helpers.exec_lua("noop = function() end")
	end)
	local shared_setup1 = [[
			local function passthrough(arg1, arg2)
				return arg1, arg2
			end

			local ed = require("luasnip.util.extend_decorator")
			ed.register(passthrough, {arg_indx = 1}, {arg_indx = 2})
	]]
	it("works", function()
		exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

		assert.is_true(exec_lua(shared_setup1 .. [[
			ext = ed.apply(passthrough, {key = "first"}, {key = "second"})
			return vim.deep_equal({ext()}, {{key = "first"}, {key = "second"}})
		]]))
	end)

	it("extended variable can be overwritten", function()
		exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

		assert.is_true(exec_lua(shared_setup1 .. [[
			ext = ed.apply(passthrough, {key = "first"}, {key = "second"})
			return vim.deep_equal({ext({key = "override_first"})}, {{key = "override_first"}, {key = "second"}})
		]]))
	end)

	it("extended variable can be overwritten", function()
		exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

		assert.is_true(exec_lua([[
			local function passthrough(arg1, arg2)
				return arg1, arg2
			end

			local ed = require("luasnip.util.extend_decorator")
			ed.register(passthrough, {arg_indx = 1, extend = function(arg, extend_arg)
				-- just something stupid to verify custom-extend works
				return {key = "custom!!"}
			end}, {arg_indx = 2})

			ext = ed.apply(passthrough, {key = "first"}, {key = "second"})
			return vim.deep_equal({ext({key = "override_first"})}, {{key = "custom!!"}, {key = "second"}})
		]]))
	end)

	it("all default-extends are registered", function()
		ls_helpers.session_setup_luasnip()

		-- think of a better way to test this here, extending+checking every arg is
		-- not feasible, so this will have to do until then.
		exec_lua([[
			local ed = ls.extend_decorator

			-- just make sure all these extends are registered.
			ed.apply(fmt)
			ed.apply(s)
			ed.apply(sn)
			ed.apply(isn)
			ed.apply(c)
			ed.apply(t)
			ed.apply(d)
			ed.apply(f)
			ed.apply(i)
			ed.apply(r)
			ed.apply(sp)
			ed.apply(parse)
			ed.apply(ls.parser.parse_snipmate)
		]])
	end)
end)
