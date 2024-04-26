-- Test longer-running sessions of snippets.
-- Should cover things like deletion (handle removed text gracefully) and insertion.
local ls_helpers = require("helpers")
local exec_lua, feed, exec =
	ls_helpers.exec_lua, ls_helpers.feed, ls_helpers.exec
local Screen = require("test.functional.ui.screen")

local function expand()
	exec_lua("ls.expand()")
end
local function jump(dir)
	exec_lua("ls.jump(...)", dir)
end
local function change(dir)
	exec_lua("ls.change_choice(...)", dir)
end

describe("session", function()
	local screen

	before_each(function()
		ls_helpers.clear()
		ls_helpers.session_setup_luasnip({
			setup_extend = { exit_roots = false },
			hl_choiceNode = true,
		})

		-- add a rather complicated snippet.
		-- It may be a bit hard to grasp, but will cover lots and lots of
		-- edge-cases.
		exec_lua([[
			local function jdocsnip(args, _, old_state)
				local nodes = {
					t({"/**"," * "}),
					old_state and i(1, old_state.descr:get_text()) or i(1, {"A short Description"}),
					t({"", ""})
				}

				-- These will be merged with the snippet; that way, should the snippet be updated,
				-- some user input eg. text can be referred to in the new snippet.
				local param_nodes = {
					descr = nodes[2]
				}

				-- At least one param.
				if string.find(args[2][1], " ") then
					vim.list_extend(nodes, {t({" * ", ""})})
				end

				local insert = 2
				for indx, arg in ipairs(vim.split(args[2][1], ", ", true)) do
					-- Get actual name parameter.
					arg = vim.split(arg, " ", true)[2]
					if arg then
						arg = arg:gsub(",", "")
						local inode
						-- if there was some text in this parameter, use it as static_text for this new snippet.
						if old_state and old_state["arg"..arg] then
							inode = i(insert, old_state["arg"..arg]:get_text())
						else
							inode = i(insert)
						end
						vim.list_extend(nodes, {t({" * @param "..arg.." "}), inode, t({"", ""})})
						param_nodes["arg"..arg] = inode

						insert = insert + 1
					end
				end

				if args[1][1] ~= "void" then
					local inode
					if old_state and old_state.ret then
						inode = i(insert, old_state.ret:get_text())
					else
						inode = i(insert)
					end

					vim.list_extend(nodes, {t({" * ", " * @return "}), inode, t({"", ""})})
					param_nodes.ret = inode
					insert = insert + 1
				end

				if vim.tbl_count(args[3]) ~= 1 then
					local exc = string.gsub(args[3][2], " throws ", "")
					local ins
					if old_state and old_state.ex then
						ins = i(insert, old_state.ex:get_text())
					else
						ins = i(insert)
					end
					vim.list_extend(nodes, {t({" * ", " * @throws "..exc.." "}), ins, t({"", ""})})
					param_nodes.ex = ins
					insert = insert + 1
				end

				vim.list_extend(nodes, {t({" */"})})

				local snip = sn(nil, nodes)
				-- Error on attempting overwrite.
				snip.old_state = param_nodes
				return snip
			end

			ls.add_snippets("all", {
				s({trig="fn"}, {
					d(6, jdocsnip, {ai[2], ai[4], ai[5]}), t({"", ""}),
					c(1, {
						t({"public "}),
						t({"private "})
					}),
					c(2, {
						t({"void"}),
						i(nil, {""}),
						t({"String"}),
						t({"char"}),
						t({"int"}),
						t({"double"}),
						t({"boolean"}),
					}),
					t({" "}),
					i(3, {"myFunc"}),
					t({"("}), i(4), t({")"}),
					c(5, {
						t({""}),
						sn(nil, {
							t({""," throws "}),
							i(1)
						})
					}),
					t({" {", "\t"}),
					i(0),
					t({"", "}"})
				})
			})
		]])

		screen = Screen.new(50, 30)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
			[4] = {
				background = Screen.colors.Red1,
				foreground = Screen.colors.White,
			},
		})
	end)

	it("Deleted snippet is handled properly in expansion.", function()
		feed("o<Cr><Cr><Up>fn")
		exec_lua("ls.expand()")
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc(^) {                            |
			                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- delete whole buffer.
		feed("<Esc>ggVGcfn")
		-- immediately expand at the old position of the snippet.
		exec_lua("ls.expand()")
		-- first jump goes to i(-1), second might go back into deleted snippet,
		-- if we did something wrong.
		jump(-1)
		jump(-1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			^/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- seven jumps to go to i(0), 8th, again, should not do anything.
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			        ^                                          |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({ unchanged = true })
	end)
	it("Deleted snippet is handled properly when jumping.", function()
		feed("o<Cr><Cr><Up>fn")
		exec_lua("ls.expand()")
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc(^) {                            |
			                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- delete whole buffer.
		feed("<Esc>ggVGd")
		-- should not cause an error.
		jump(1)
	end)
	it("Deleting nested snippet only removes it.", function()
		feed("o<Cr><Cr><Up>fn")
		exec_lua("ls.expand()")
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		feed("<Esc>jlafn")
		expand()
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			        /**                                       |
			         * A short Description                    |
			         */                                       |
			        ^public void myFunc() { {4:●}                  |
			                                                  |
			        }                                         |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		jump(1)
		jump(1)
		feed("<Esc>llllvbbbx")
		-- first jump goes into function-arguments, second will trigger update,
		-- which will in turn recognize the broken snippet.
		-- The third jump will then go into the outer snippet.
		jump(1)
		jump(1)
		jump(-1)
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * ^A{3: short Description}                            |
			 */                                               |
			public void myFunc() {                            |
			        /**                                       |
			         * A short Description                    |
			         */                                       |
			        c() {                                     |
			                                                  |
			        }                                         |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
		-- this should jump into the $0 of the outer snippet, highlighting the
		-- entire nested snippet.
		jump(1)
		screen:expect({
			grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			        ^/{3:**}                                       |
			{3:         * A short Description}                    |
			{3:         */}                                       |
			{3:        c() {}                                     |
			{3:                }                                  |
			{3:        }}                                         |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)
	for _, link_roots_val in ipairs({ "true", "false" }) do
		it(
			("Snippets are inserted according to link_roots and keep_roots=%s"):format(
				link_roots_val
			),
			function()
				exec_lua(([[
				ls.setup({
					keep_roots = %s,
					link_roots = %s
				})
			]]):format(link_roots_val, link_roots_val))

				feed("ifn")
				expand()
				-- "o" does not extend the extmark of the active snippet.
				feed("<Esc>Go<Cr>fn")
				expand()
				jump(-1)
				jump(-1)
				-- if linked, should end up back in the original snippet, if not,
				-- stay in second.
				if link_roots_val == "true" then
					screen:expect({
						grid = [[
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					        ^                                          |
					}                                                 |
					                                                  |
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					                                                  |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- INSERT --}                                      |]],
					})
				else
					screen:expect({
						grid = [[
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					                                                  |
					}                                                 |
					                                                  |
					^/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					                                                  |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- INSERT --}                                      |]],
					})
				end
			end
		)
	end
	for _, keep_roots_val in ipairs({ "true", "false" }) do
		it("Root-snippets are stored iff keep_roots=true", function()
			exec_lua(([[
				ls.setup({
					keep_roots = %s,
				})
			]]):format(keep_roots_val, keep_roots_val))

			feed("ifn")
			expand()
			-- "o" does not extend the extmark of the active snippet.
			feed("<Esc>Go<Cr>fn")
			expand()

			-- jump into insert-node in first snippet.
			local err = exec_lua(
				[[return {pcall(ls.activate_node, {pos = {1, 8}})}]]
			)[2]

			-- if linked, should end up back in the original snippet, if not,
			-- stay in second.
			if keep_roots_val == "true" then
				screen:expect({
					grid = [[
				/**                                               |
				 * ^A{3: short Description}                            |
				 */                                               |
				public void myFunc() {                            |
				                                                  |
				}                                                 |
				                                                  |
				/**                                               |
				 * A short Description                            |
				 */                                               |
				public void myFunc() {                            |
				                                                  |
				}                                                 |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- SELECT --}                                      |]],
				})
			else
				assert(err:match("No Snippet at that position"))
			end
		end)
	end
	for _, link_children_val in ipairs({ "true", "false" }) do
		it("Child-snippets are linked iff link_children=true", function()
			exec_lua(([[
				ls.setup({
					link_children = %s,
					exit_roots = false,
				})
			]]):format(link_children_val))

			feed("ifn")
			expand()
			-- expand child-snippet in $0 of original snippet.
			feed("<Esc>jafn")
			expand()
			-- expand another child.
			feed("<Esc>jjAfn")
			expand()
			screen:expect({
				grid = [[
				/**                                               |
				 * A short Description                            |
				 */                                               |
				public void myFunc() {                            |
				        /**                                       |
				         * A short Description                    |
				         */                                       |
				        public void myFunc() {                    |
				                                                  |
				        }/**                                      |
				         * A short Description                    |
				         */                                       |
				        ^public void myFunc() {                    |
				                                                  |
				        }                                         |
				}                                                 |
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{0:~                                                 }|
				{2:-- INSERT --}                                      |]],
			})

			-- if linked, should end up back in the original snippet, if not,
			-- stay in second.
			if link_children_val == "true" then
				-- make sure we can jump into the previous child...
				jump(-1)
				jump(-1)
				screen:expect({
					grid = [[
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					        /**                                       |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                ^                                  |
					        }/**                                      |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }                                         |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- INSERT --}                                      |]],
				})
				-- ...and from the first child back into the parent...
				jump(-1)
				jump(-1)
				jump(-1)
				jump(-1)
				jump(-1)
				jump(-1)
				jump(-1)
				jump(-1)
				screen:expect({
					grid = [[
					/**                                               |
					 * ^A{3: short Description}                            |
					 */                                               |
					public void myFunc() {                            |
					        /**                                       |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }/**                                      |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }                                         |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- SELECT --}                                      |]],
				})
				-- ...and back to the end of the second snippet...
				-- (first only almost to the end, to make sure we makde the correct number of jumps).
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				jump(1)
				screen:expect({
					grid = [[
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					        /**                                       |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }/**                                      |
					         * ^A{3: short Description}                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }                                         |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- SELECT --}                                      |]],
				})
				jump(1)
				screen:expect({
					grid = [[
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					        /**                                       |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }/**                                      |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                ^                                  |
					        }                                         |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- INSERT --}                                      |]],
				})
				-- test inability to jump beyond a few times, I've had bugs
				-- where after a multiple jumps, a new node became active.
				jump(1)
				screen:expect({ unchanged = true })
				jump(1)
				screen:expect({ unchanged = true })
				jump(1)
				screen:expect({ unchanged = true })

				-- For good measure, make sure the node is actually still active.
				jump(-1)
				screen:expect({
					grid = [[
					/**                                               |
					 * A short Description                            |
					 */                                               |
					public void myFunc() {                            |
					        /**                                       |
					         * A short Description                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }/**                                      |
					         * ^A{3: short Description}                    |
					         */                                       |
					        public void myFunc() {                    |
					                                                  |
					        }                                         |
					}                                                 |
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{0:~                                                 }|
					{2:-- SELECT --}                                      |]],
				})
			else
			end
		end)
	end
	it("Snippets with destroyed extmarks are not used as parents.", function()
		feed("ifn")
		expand()
		-- delete the entier text of a textNode, which will make
		-- extmarks_valid() false.
		feed("<Esc>eevllx")
		-- insert snippet inside the invalid parent.
		feed("jAfn")
		expand()
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public voiyFunc() {                               |
			        /**                                       |
			         * A short Description                    |
			         */                                       |
			        ^public void myFunc() { {4:●}                  |
			                                                  |
			        }                                         |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- make sure the parent is invalid.
		jump(-1)
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public voiyFunc() {                               |
			        ^/**                                       |
			         * A short Description                    |
			         */                                       |
			        public void myFunc() {                    |
			                                                  |
			        }                                         |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- should not move back into the parent.
		jump(-1)
		screen:expect({ unchanged = true })
	end)
	it("region_check_events works correctly", function()
		exec_lua([[
			ls.setup({
				history = true,
				region_check_events = {"CursorHold", "InsertLeave"},
				ext_opts = {
					[require("luasnip.util.types").choiceNode] = {
						active = {
							virt_text = {{"●", "ErrorMsg"}},
							priority = 0
						},
					}
				},
			})
		]])

		-- expand snippet.
		feed("ifn")
		expand()
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- leave its region.
		feed("<Esc>Go<Esc>")
		-- check we have left the snippet (choiceNode indicator no longer active).
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			^                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			                                                  |]],
		})

		-- re-activate $0, expand child.
		jump(-1)
		jump(1)
		feed("fn")
		expand()

		-- jump behind child, activate region_leave, make sure the child and
		-- root-snippet are _not_ exited.
		feed("<Esc>jjA<Esc>o<Esc>")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			        /**                                       |
			         * A short Description                    |
			         */                                       |
			        public void myFunc() { {4:●}                  |
			                                                  |
			        }                                         |
			^                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			                                                  |]],
		})
		-- .. and now both are left upon leaving the region of the root-snippet.
		feed("<Esc>jji<Esc>")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			        /**                                       |
			         * A short Description                    |
			         */                                       |
			        public void myFunc() {                    |
			                                                  |
			        }                                         |
			                                                  |
			}                                                 |
			^                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			                                                  |]],
		})
	end)
	it("delete_check_events works correctly", function()
		exec_lua([[
			ls.setup({
				history = true,
				delete_check_events = "TextChanged",
				ext_opts = {
					[require("luasnip.util.types").choiceNode] = {
						active = {
							virt_text = {{"●", "ErrorMsg"}},
							priority = 0
						},
					}
				},
			})
		]])

		-- expand.
		feed("ifn")
		expand()
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- delete textNode, to trigger unlink_current_if_deleted via esc.
		feed("<Esc>eevllx<Esc>")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public voi^yFunc() {                               |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			                                                  |]],
		})
		jump(1)
		screen:expect({ unchanged = true })
	end)
	it("Insertion into non-interactive node works correctly", function()
		feed("ifn")
		expand()

		-- expand snippet in textNode, ie. s.t. it can't be properly linked up.
		feed("<Esc>kifn")
		expand()
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			} */                                              |
			public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- jump into startNode, and back into current node.
		jump(-1)
		jump(-1)
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			} */                                              |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- check jumping out in other direction.
		feed("<Esc>jjifn")
		expand()
		-- jump to one before jumping out of child-snippet.
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			} */                                              |
			public void myFunc() { {4:●}                          |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			        ^                                          |
			}}                                                |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- leave child.
		jump(1)
		-- check back in current node.
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			} */                                              |
			^public void myFunc() { {4:●}                          |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}}                                                |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)
	it("All operations work as expected in a longer session.", function()
		exec_lua([[
			ls.setup({
				keep_roots = true,
				link_roots = true,
				exit_roots = false,
				link_children = true,
				delete_check_events = "TextChanged",
				ext_opts = {
					[require("luasnip.util.types").choiceNode] = {
						active = {
							virt_text = {{"●", "ErrorMsg"}},
							priority = 0
						},
					}
				},
			})
		]])
		feed("ifn")
		expand()
		feed("<Esc>kkwwwifn")
		expand()
		screen:expect({
			grid = [[
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 ^public void myFunc() { {4:●}                         |
			                                                  |
			 }short Description                               |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>ggOfn")
		expand()
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }short Description                               |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- ensure correct linkage.
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }short Description                               |
			 */                                               |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- enter third choiceNode of second expanded snippet.
		feed("<Esc>kkkk$h")
		exec_lua([[require("luasnip").activate_node()]])
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc()^ { {4:●}                         |
			                                                  |
			 }short Description                               |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- check connectivity.
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		jump(1)
		exec_lua("vim.wait(10, function() end)")
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }short Description                               |
			 */                                               |
			public void myFunc() {                            |
			        ^                                          |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
		-- stay at last node.
		jump(1)
		screen:expect({ unchanged = true })

		-- expand in textNode.
		feed("<Esc>kkbifn")
		expand()

		-- check connectivity.
		jump(-1)
		jump(-1)
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			/**                                               |
			 * ^A{3: /**}                                          |
			{3:  * A short Description}                           |
			{3:  */}                                              |
			{3: public void myFunc() {}                           |
			{3:        }                                          |
			{3: }short Description}                               |
			 /**                                              |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }*/                                              |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})

		-- end up back in last node, not in textNode-expanded snippet.
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		screen:expect({
			grid = [[
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }short Description                               |
			 /**                                              |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }*/                                              |
			public void myFunc() {                            |
			        ^                                          |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>gg")
		exec_lua([[require("luasnip").activate_node()]])

		feed("<Esc>Vjjjjjx")
		exec_lua("ls.unlink_current_if_deleted()")
		screen:expect({
			grid = [[
			^/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }short Description                               |
			 /**                                              |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }*/                                              |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			6 fewer lines                                     |]],
		})
		-- first snippet is active again.
		jump(1)
		screen:expect({
			grid = [[
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }short Description                               |
			 /**                                              |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }*/                                              |
			^public void myFunc() { {4:●}                          |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		-- make sure the deleted snippet got disconnected properly.
		assert.are.same(
			exec_lua(
				[[return ls.session.current_nodes[1].parent.snippet.prev.prev and "Node before" or "No node before"]]
			),
			"No node before"
		)

		-- jump a bit into snippet, so exit_out_of_region changes the current snippet.
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		jump(1)
		screen:expect({
			grid = [[
			/**                                               |
			 * A /**                                          |
			  * A short Description                           |
			  */                                              |
			 ^public void myFunc() { {4:●}                         |
			                                                  |
			 }short Description                               |
			 /**                                              |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }*/                                              |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})

		feed("<Esc>Go")
		exec_lua("ls.exit_out_of_region(ls.session.current_nodes[1])")
		jump(-1)
		screen:expect({
			grid = [[
			/**                                               |
			 * ^A{3: /**}                                          |
			{3:  * A short Description}                           |
			{3:  */}                                              |
			{3: public void myFunc() {}                           |
			{3:        }                                          |
			{3: }short Description}                               |
			 /**                                              |
			  * A short Description                           |
			  */                                              |
			 public void myFunc() {                           |
			                                                  |
			 }*/                                              |
			public void myFunc() {                            |
			                                                  |
			}                                                 |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
		})
	end)

	it(
		"Refocus works correctly when functionNode moves focus during refocus, and `to` is not `input_enter`ed.",
		function()
			exec_lua([[
			ls.setup({
				keep_roots = true,
				link_roots = true,
				exit_roots = false,
				link_children = true
			})
		]])
			screen:detach()
			screen = Screen.new(50, 4)
			screen:attach()
			screen:set_default_attr_ids({
				[0] = { bold = true, foreground = Screen.colors.Blue },
				[1] = { bold = true, foreground = Screen.colors.Brown },
				[2] = { bold = true },
				[3] = { background = Screen.colors.LightGray },
				[4] = {
					background = Screen.colors.Red1,
					foreground = Screen.colors.White,
				},
			})

			exec_lua([[
			ls.add_snippets("all", {
				s("tricky", {
					-- add some text before snippet to make sure a snippet
					-- expanded in i(1) will expand inside the snippet, not
					-- before it.
					t"|", i(1, "1234"), f(function()
						return "asdf"
					-- depend on first insertNode, so that this fNode is
					-- updated when i(1) is changed.
					end, {1})
				}),
				s("dummy", { t"qwer" })
			})
		]])

			feed("itricky")
			expand()
			feed("dummy")
			expand()
			feed("<Space>dummy")
			expand()
			screen:expect({
				grid = [[
			|qwer qwer^asdf                                    |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
			jump(1)
			jump(-1)
			-- Bad:
			-- screen:expect{grid=[[
			--   |^q{3:wer }qwerasdf                                    |
			--   {0:~                                                 }|
			--   {0:~                                                 }|
			--   {2:-- SELECT --}                                      |
			-- ]]}

			-- Good:
			screen:expect({
				grid = [[
			|^q{3:wer qwer}asdf                                    |
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})
		end
	)

	it(
		"snippet_roots stays an array if a snippet-root is removed during refocus, during trigger_expand.",
		function()
			exec_lua([[
			ls.setup({
				keep_roots = true,
				-- don't update immediately; we want to ensure removal of the
				-- snippet due to update of deleted nodes, and we have to
				-- delete them before the update is triggered via autocmd
				update_events = "BufWritePost"
			})
		]])

			feed("o<Cr><Cr><Cr><Esc>kkifn")
			expand()
			jump(1)
			exec_lua("vim.wait(10, function() end)")
			jump(1)
			exec_lua("vim.wait(10, function() end)")
			jump(1)
			exec_lua("vim.wait(10, function() end)")
			feed("int a")
			screen:expect({
				grid = [[
			                                                  |
			                                                  |
			/**                                               |
			 * A short Description                            |
			 */                                               |
			public void myFunc(int a^) {                       |
			                                                  |
			}                                                 |
			                                                  |
			                                                  |
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})

			-- delete snippet-text while an update for the dynamicNode is pending
			-- => when the dynamicNode is left during `refocus`, the deletion will
			-- be detected, and snippet removed from the jumplist.
			feed("<Esc>kkkVjjjjjd")

			feed("jifn")
			expand()

			-- make sure the snippet-roots-list is still an array, and we did not
			-- insert at 2 after the deletion of the first snippet.
			assert(exec_lua("return ls.session.snippet_roots[1][1] ~= nil"))
			assert(exec_lua("return ls.session.snippet_roots[1][2] == nil"))
		end
	)

	it(
		"sibling-snippet's extmarks are shifted away before insertion.",
		function()
			screen:detach()
			-- make screen smaller :)
			screen = Screen.new(50, 3)
			screen:attach()
			screen:set_default_attr_ids({
				[0] = { bold = true, foreground = Screen.colors.Blue },
				[1] = { bold = true, foreground = Screen.colors.Brown },
				[2] = { bold = true },
				[3] = { background = Screen.colors.LightGray },
				[4] = {
					background = Screen.colors.Red1,
					foreground = Screen.colors.White,
				},
			})

			exec_lua([[
			ls.setup{
				link_children = true
			}
			ls.add_snippets("all", {
				s({
					trig = '_',
					wordTrig = false,
				}, {
					t('_'),
					i(1),
				}),
				ls.parser.parse_snippet({trig="(", wordTrig=false}, "($1)"),
			})
		]])

			feed("i(")
			expand()
			feed("n_")
			expand()
			feed("h")
			screen:expect({
				grid = [[
			(n_h^)                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
			})
			-- jumped behind the insertNode, into $0.
			jump(1)

			feed("(")
			expand()
			feed("asdf")
			jump(-1)
			jump(-1)
			jump(-1)
			-- make sure that we only select h, ie. that the insertNode only
			-- contains h, and not the ()-snippet.
			screen:expect({
				grid = [[
			(n_^h(asdf))                                       |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]],
			})
		end
	)
end)
