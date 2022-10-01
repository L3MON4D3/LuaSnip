local helpers = require("test.functional.helpers")(after_each)
local ls_helpers = require("helpers")

describe("expand_conditions", function()
	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()
		helpers.exec_lua("noop = function() end")
	end)

	-- apparently clear() needs to run before anything else...
	helpers.clear()
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))
	it("simple", function()
		local function foo()
			return helpers.exec_lua([[
			local mkcond = require("luasnip.extras.conditions").make_condition
			local c = mkcond(function() return true end)
			return c() == true
			]])
		end
		assert.has_no.errors(foo)
		assert.is_true(foo())
	end)
	describe("logic ops", function()
		describe("and", function()
			local function foo(b1, b2)
				-- Attention: use this only when testing (otherwise (pot.
				-- malicious) users might inject code)
				return helpers.exec_lua(
					([[
					local mkcond = require("luasnip.extras.conditions").make_condition
					local c = mkcond(function() return %s end) * mkcond(function() return %s end)
					return c() == %s
					]]):format(
						tostring(b1),
						tostring(b2),
						tostring(b1 and b2)
					)
				)
			end
			for _, ele in ipairs({
				{ true, true },
				{ true, false },
				{ false, true },
				{ false, false },
			}) do
				it(
					("%s and %s"):format(tostring(ele[1]), tostring(ele[2])),
					function()
						local test = function()
							return foo(ele[1], ele[2])
						end
						assert.has_no.errors(test)
						assert.is_true(test())
					end
				)
			end
		end)
		describe("or", function()
			local function foo(b1, b2)
				-- Attention: use this only when testing (otherwise (pot.
				-- malicious) users might inject code)
				return helpers.exec_lua(([[
					local mkcond = require("luasnip.extras.conditions").make_condition
					local c = mkcond(function() return %s end) + mkcond(function() return %s end)
					return c() == %s
					]]):format(tostring(b1), tostring(b2), tostring(b1 or b2)))
			end
			for _, ele in ipairs({
				{ true, true },
				{ true, false },
				{ false, true },
				{ false, false },
			}) do
				it(
					("%s or %s"):format(tostring(ele[1]), tostring(ele[2])),
					function()
						local test = function()
							return foo(ele[1], ele[2])
						end
						assert.has_no.errors(test)
						assert.is_true(test())
					end
				)
			end
		end)
		describe("xor", function()
			local function foo(b1, b2)
				-- Attention: use this only when testing (otherwise (pot.
				-- malicious) users might inject code)
				return helpers.exec_lua(
					([[
					local mkcond = require("luasnip.extras.conditions").make_condition
					local c = mkcond(function() return %s end) ^ mkcond(function() return %s end)
					return c() == %s
					]]):format(
						tostring(b1),
						tostring(b2),
						tostring((b1 and not b2) or (not b1 and b2))
					)
				)
			end
			for _, ele in ipairs({
				{ true, true },
				{ true, false },
				{ false, true },
				{ false, false },
			}) do
				it(
					("%s xor %s"):format(tostring(ele[1]), tostring(ele[2])),
					function()
						local test = function()
							return foo(ele[1], ele[2])
						end
						assert.has_no.errors(test)
						assert.is_true(test())
					end
				)
			end
		end)
		describe("xnor", function()
			local function foo(b1, b2)
				-- Attention: use this only when testing (otherwise (pot.
				-- malicious) users might inject code)
				return helpers.exec_lua(([[
					local mkcond = require("luasnip.extras.conditions").make_condition
					local c = mkcond(function() return %s end) %% mkcond(function() return %s end)
					return c() == %s
					]]):format(tostring(b1), tostring(b2), tostring(b1 == b2)))
			end
			for _, ele in ipairs({
				{ true, true },
				{ true, false },
				{ false, true },
				{ false, false },
			}) do
				it(
					("%s xnor %s"):format(tostring(ele[1]), tostring(ele[2])),
					function()
						local test = function()
							return foo(ele[1], ele[2])
						end
						assert.has_no.errors(test)
						assert.is_true(test())
					end
				)
			end
		end)
		describe("not", function()
			local function foo(b1)
				-- Attention: use this only when testing (otherwise (pot.
				-- malicious) users might inject code)
				return helpers.exec_lua(([[
					local mkcond = require("luasnip.extras.conditions").make_condition
					local c = -mkcond(function() return %s end)
					return c() == %s
					]]):format(tostring(b1), tostring(not b1)))
			end
			for _, ele in ipairs({ { true }, { false } }) do
				it(("not %s"):format(tostring(ele[1])), function()
					local test = function()
						return foo(ele[1])
					end
					assert.has_no.errors(test)
					assert.is_true(test())
				end)
			end
		end)
		describe("composite", function()
			local function foo(b1, b2, b3)
				-- Attention: use this only when testing (otherwise (pot.
				-- malicious) users might inject code)
				return helpers.exec_lua(
					([[
					local mkcond = require("luasnip.extras.conditions").make_condition
					local c = - ( mkcond(function() return %s end) + mkcond(function() return %s end) * mkcond(function() return %s end)) ^ ( mkcond(function() return %s end) + mkcond(function() return %s end) * mkcond(function() return %s end))
					return c() == %s
					]]):format(
						tostring(b1),
						tostring(b2),
						tostring(b3),
						tostring(b3),
						tostring(b1),
						tostring(b2),
						tostring(not (b1 or b2 and b3) ~= (b3 or b1 and b2))
					)
				)
			end
			for _, ele in ipairs({
				{ true, true, true },
				{ true, true, false },
				{ true, false, true },
				{ true, false, false },
				{ false, true, true },
				{ false, true, false },
				{ false, false, true },
				{ false, false, false },
			}) do
				it(
					("composite %s %s %s"):format(
						tostring(ele[1]),
						tostring(ele[2]),
						tostring(ele[3])
					),
					function()
						local test = function()
							return foo(ele[1], ele[2], ele[3])
						end
						assert.has_no.errors(test)
						assert.is_true(test())
					end
				)
			end
		end)
	end)
	describe("line_begin", function()
		it("is at begin", function()
			local function foo()
				return helpers.exec_lua([[
				local conds = require("luasnip.extras.expand_conditions")
				local c = conds.line_begin
				return not c("hello world", "hello world") ~= true -- allow nil/object
				]])
			end
			assert.has_no.errors(foo)
			assert.is_true(foo())
		end)
		it("is NOT at begin", function()
			local function foo()
				return helpers.exec_lua([[
				local conds = require("luasnip.extras.expand_conditions")
				local c = conds.line_begin
				return not c("hello world", "ld") ~= false -- allow nil/object
				]])
			end
			assert.has_no.errors(foo)
			assert.is_true(foo())
		end)
	end)
	describe("line_end", function()
		it("is at begin", function()
			local function foo()
				return helpers.exec_lua([[
				local vim_bak = vim
				-- vim.api.nvim_get_current_line
				vim = {api = {nvim_get_current_line = function() return "hello world ending" end}}
				local conds = require("luasnip.extras.expand_conditions")
				local c = conds.line_end
				local ret = not c("hello world ending") ~= true -- allow nil/object
				vim = vim_bak
				return ret
				]])
			end
			assert.has_no.errors(foo)
			assert.is_true(foo())
		end)
		it("is NOT at begin", function()
			local function foo()
				return helpers.exec_lua([[
				local vim_bak = vim
				-- vim.api.nvim_get_current_line
				vim = {api = {nvim_get_current_line = function() return "hello world ending" end}}
				local conds = require("luasnip.extras.expand_conditions")
				local c = conds.line_end
				local ret = not c("hello world") ~= false -- allow nil/object
				vim = vim_bak
				return ret
				]])
			end
			assert.has_no.errors(foo)
			assert.is_true(foo())
		end)
	end)
end)
