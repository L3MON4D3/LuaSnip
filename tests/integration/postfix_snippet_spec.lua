local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed, exec = helpers.exec_lua, helpers.feed, helpers.exec
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("postfix snippets", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it(
		"creates a postfix snippet which changes the previous text once expanded",
		function()
			local postfix_snip = [[
	    pf(".parens", {
	      f(function(_, parent)
	        return "(" .. parent.env.POSTFIX_MATCH .. ")"
        end, {})
      })
	  ]]

			feed("ibar")
			exec_lua("ls.snip_expand(" .. postfix_snip .. ")")
			screen:expect({
				grid = [[
          (bar)^                                             |
          {0:~                                                 }|
          {2:-- INSERT --}                                      |
        ]],
			})
		end
	)

	it("default pattern works with a _, -, and .", function()
		local postfix_snip = [[
	    pf(".parens", {
	      f(function(_, parent)
	        return "(" .. parent.env.POSTFIX_MATCH .. ")"
        end, {})
      })
	  ]]

		feed("ithis_is-a.weird_variable")
		exec_lua("ls.snip_expand(" .. postfix_snip .. ")")

		screen:expect({
			grid = [[
        (this_is-a.weird_variable)^                        |
        {0:~                                                 }|
        {2:-- INSERT --}                                      |
      ]],
		})
	end)

	it("can take alternate matching strings", function()
		local postfix_snip = [[
	    pf({trig = ".parens", match_pattern = "^.+$"}, {
	      f(function(_, parent)
	        return "(" .. parent.env.POSTFIX_MATCH .. ")"
        end, {})
      })
	  ]]

		feed([[ithis should take the whole line]])
		exec_lua("ls.snip_expand(" .. postfix_snip .. ")")

		screen:expect({
			grid = [[
        (this should take the whole line)^                 |
        {0:~                                                 }|
        {2:-- INSERT --}                                      |
      ]],
		})
	end)

	it("wordTrig can't accidentally be set", function()
		local postfix_snip = [[
	    pf({trig = ".parens", match_pattern = "^.+$", wordTrig = true}, {
	      f(function(_, parent)
	        return "(" .. parent.env.POSTFIX_MATCH .. ")"
        end, {})
      })
	  ]]

		feed([[ithis should take the whole line]])
		exec_lua("ls.snip_expand(" .. postfix_snip .. ")")

		screen:expect({
			grid = [[
        (this should take the whole line)^                 |
        {0:~                                                 }|
        {2:-- INSERT --}                                      |
      ]],
		})
	end)

	it("allows the user to set a callback on the same event", function()
		local postfix_snip = [[
      pf(
        ".parens",
        {
          f(function(_, parent)
            return "("
              .. parent.env.POSTFIX_MATCH
              .. " "
              .. parent.env.another_field 
              .. ")"
          end),
        },
        {
          callbacks = {
            [-1] = {
              [events.pre_expand] = function(snippet, event_args)
                return {
                  env_override = {
                    another_field = "data from another env field",
                  },
                }
              end,
            },
          },
        }
      )
	  ]]

		feed([[ifoo]])
		exec_lua("ls.snip_expand(" .. postfix_snip .. ")")

		screen:expect({
			grid = [[
      (foo data from another env field)^                 |
      {0:~                                                 }|
      {2:-- INSERT --}                                      |
    ]],
		})
	end)
end)
