local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua

describe("luasnip.util.environ", function()
	local function check_not_empty(test_name, namespace_setup, var_name)
		it(test_name, function()
			assert.is_true(
				exec_lua(
					([=[
					local Environ = require("luasnip.util.environ")
                                        %s

                                        local env = Environ:new({0, 0})
                                        local result = env["%s"]
                                        return #(result) > 0
                                        ]=]):format(
						namespace_setup,
						var_name
					)
				)
			)
		end)
	end

	local function check_value(test_name, namespace_setup, var_name, val)
		it(test_name, function()
			assert.are.equal(
				exec_lua(
					([=[
					local Environ = require("luasnip.util.environ")
                                        %s

                                        local env = Environ:new({0, 0})
                                        return env["%s"]
                                        ]=]):format(
						namespace_setup,
						var_name
					)
				),
				val
			)
		end)
	end
	local function check_undefined(test_name, namespace_setup, var_name)
		it(test_name, function()
			assert.is_true(
				exec_lua(
					([=[
					local Environ = require("luasnip.util.environ")
                                        %s
                                        local env = Environ:new({0, 0})
                                        return env["%s"] == nil
                                        ]=]):format(
						namespace_setup,
						var_name
					)
				)
			)
		end)
	end

	local function check_var_is_eager(
		test_name,
		namespace_setup,
		var_name,
		eager
	)
		it(test_name, function()
			assert.are.equal(
				exec_lua(
					([=[
					local Environ = require("luasnip.util.environ")
                                        %s
                                        local env = Environ:new({0, 0})
                                        return rawget(env, "%s") ~= nil
                                        ]=]):format(
						namespace_setup,
						var_name
					)
				),
				eager
			)
		end)
	end

	local function check(test_name, namespace_setup, var_name, eager, value)
		check_undefined(test_name .. " without initialization", [[]], var_name)
		check_var_is_eager(
			test_name .. " lazyness",
			namespace_setup,
			var_name,
			eager or false
		)
		if value then
			check_value(
				test_name .. " with initialization",
				namespace_setup,
				var_name,
				value
			)
		else
			check_not_empty(
				test_name .. " with initialization",
				namespace_setup,
				var_name
			)
		end
	end

	local function check_fails(test_name, namespace_setup)
		it(test_name .. " MUST fail", function()
			assert.is_false(
				exec_lua(
					([=[
					local Environ = require("luasnip.util.environ")
                                        return pcall(function()
                                            %s
                                            end
                                        )
                                        ]=]):format(
						namespace_setup
					)
				)
			)
		end)
	end
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	check_not_empty("Has builtin namespace var", [[]], "CURRENT_YEAR")
	check_not_empty(
		"Has a builtin namespace var without _ in its name",
		[[]],
		"UUID"
	)
	check(
		"Simple lazy table",
		[[Environ.env_namespace("TBL", {vars={AGE="120"}} )]],
		"TBL_AGE"
	)
	check(
		"Lazy funtion",
		[[Environ.env_namespace("FN", {vars=function(n) return n end} )]],
		"FN_VAR",
		false,
		"VAR"
	)
	check(
		"Init funtion",
		[[Environ.env_namespace("IN", {init=function(pos) return {POS = table.concat(pos, ',')} end})]],
		"IN_POS",
		true,
		"0,0"
	)
	check(
		"Lazy funtion with eager",
		[[Environ.env_namespace("EG", {vars=function(n) return n end, eager={"VAR"}} )]],
		"EG_VAR",
		true,
		"VAR"
	)

	check_fails(
		"Environ with invalid name",
		[[Environ.env_namespace("TES_T", {vars={AGE="120"}})]]
	)
	check_fails(
		"Environ with invalid name",
		[[Environ.env_namespace("TES_T", {vars={AGE="120"}})]]
	)
	check_fails("Environ without opts", [[Environ.env_namespace("TES_T")]])
	check_fails(
		"Environ without init or vars",
		[[Environ.env_namespace("TES_T", {})]]
	)
	check_fails(
		"Environ with eager but no vars",
		[[Environ.env_namespace("TES_T", {eager={"A"}})]]
	)
	check_fails(
		"Environ with multiline_vars incorrect type",
		[[Environ.env_namespace("TES_T", {var={A='s', multiline_vars = 9 }})]]
	)
end)
