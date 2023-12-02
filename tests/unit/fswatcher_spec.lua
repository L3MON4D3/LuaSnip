local helpers = require("test.functional.helpers")()
local exec_lua = helpers.exec_lua
local ls_helpers = require("helpers")
local mkdir = ls_helpers.scratch_mkdir
local touch = ls_helpers.scratch_touch
local edit = ls_helpers.scratch_edit

describe("fs_events", function()
	before_each(function()
		helpers.clear()

		ls_helpers.session_setup_luasnip()
		ls_helpers.scratch_prepare()

		exec_lua([[ls.log.set_loglevel("debug")]])
	end)
	after_each(function()
		ls_helpers.scratch_clear()
	end)

	it("works with libuv-event-provider.", function()
		mkdir("a")
		mkdir("a/1")
		mkdir("a/2")
		mkdir("a/3")
		touch("a/1/b")
		mkdir("a/3/b/c")
		touch("a/3/b/d")

		exec_lua([[
			seen_files = {
				["a/1/a"] = 0,
				["a/1/b"] = 0,
				["a/3/b/d"] = 0,
				["a/4/a/a"] = 0,
				["a/4/a/b/a"] = 0,
			}
			seen_dirs = {
				["a/1"] = 0,
				["a/2"] = 0,
				["a/3"] = 0,
				["a/3/b"] = 0,
				["a/3/b/c"] = 0,
				["a/4"] = 0,
				["a/4/a"] = 0,
				["a/4/a/b"] = 0,
			}
			changed = {
				["a/1/b"] = 0,
				["a/1/a"] = 0,
			}

			watcher = scratch_tree_watcher("a", 3, {
				new_file = function(path)
					seen_files[path] = seen_files[path] + 1
				end,
				new_dir = function(path)
					seen_dirs[path] = seen_dirs[path] + 1
				end,
				change_file = function(path)
					changed[path] = changed[path] + 1
				end
			}, {lazy=false, fs_event_providers = {libuv = true, autocmd = false} } )
		]])

		-- new file.
		touch("a/1/a")

		-- wait for a/1/a to be recognized...
		exec_lua("vim.wait(10, function() end)")

		-- ... then change and wait again.
		touch("a/1/a")
		touch("a/1/b")

		exec_lua("vim.wait(10, function() end)")

		mkdir("a/4/a")
		touch("a/4/a/a")
		mkdir("a/4/a/b")

		-- this should not be reported, due to depth.
		touch("a/4/a/b/a")

		exec_lua("vim.wait(10, function() end)")

		assert.are.same({
			{
				-- files
				["a/1/a"] = 1,
				["a/1/b"] = 1,
				["a/3/b/d"] = 1,
				["a/4/a/a"] = 1,
				["a/4/a/b/a"] = 0,
			},
			{
				-- directories
				["a/1"] = 1,
				["a/2"] = 1,
				["a/3"] = 1,
				["a/3/b"] = 1,
				["a/3/b/c"] = 1,
				["a/4"] = 1,
				["a/4/a"] = 1,
				["a/4/a/b"] = 1,
			},
			{
				-- changed files

				-- this is reported twice, once on create, once on the actual change.
				-- Maybe a small peculiarity to watch out for, but does not seem bad.
				["a/1/a"] = 2,
				["a/1/b"] = 1,
			},
		}, exec_lua([[return {seen_files, seen_dirs, changed}]]))
	end)

	it("works with autocmd-event-provider.", function()
		mkdir("a")
		edit("a/1/b")
		edit("a/3/b/d")

		exec_lua([[
			seen_files = {
				["a/1/a"] = 0,
				["a/1/b"] = 0,
				["a/3/b/d"] = 0,
				["a/4/a/a"] = 0,
				["a/4/a/b/a"] = 0,
			}
			seen_dirs = {
				["a/1"] = 0,
				["a/3"] = 0,
				["a/3/b"] = 0,
				["a/4"] = 0,
				["a/4/a"] = 0,
				["a/4/a/b"] = 0,
			}
			changed = {
				["a/1/b"] = 0,
				["a/1/a"] = 0,
				["a/4/a/a"] = 0,
				["a/4/a/b/a"] = 0
			}

			watcher = scratch_tree_watcher("a", 3, {
				new_file = function(path)
					-- os.execute("echo qwerqwerqwer   " .. path .. " >> asdf")
					seen_files[path] = seen_files[path] + 1
					-- os.execute("echo qwerqwerqwes   " .. path .. " >> asdf")
				end,
				new_dir = function(path)
					-- os.execute("echo qwerqwerqwer" .. path .. " >> asdf")
					seen_dirs[path] = seen_dirs[path] + 1
				end,
				change_file = function(path)
					-- os.execute("echo change " .. path .. " >> asdf")
					changed[path] = changed[path] + 1
				end
			}, {lazy=false, fs_event_providers = {libuv = false, autocmd = true} } )
		]])

		-- new file.
		edit("a/1/a")

		-- wait for a/1/a to be recognized...
		exec_lua("vim.wait(10, function() end)")

		-- ... then change.
		edit("a/1/a")

		edit("a/1/b")

		exec_lua("vim.wait(10, function() end)")

		edit("a/4/a/a")

		-- this should not be reported, due to depth.
		edit("a/4/a/b/a")

		exec_lua("vim.wait(10, function() end)")

		assert.are.same({
			{
				["a/1/a"] = 1,
				["a/1/b"] = 1,
				["a/3/b/d"] = 1,
				["a/4/a/a"] = 1,
				["a/4/a/b/a"] = 0,
			},
			{
				["a/1"] = 1,
				["a/3"] = 1,
				["a/3/b"] = 1,
				["a/4"] = 1,
				["a/4/a"] = 1,
				["a/4/a/b"] = 1,
			},
			{
				["a/1/b"] = 1,
				["a/1/a"] = 1,
				["a/4/a/a"] = 1,
				-- to deep.
				["a/4/a/b/a"] = 0,
			},
		}, exec_lua([[return {seen_files, seen_dirs, changed}]]))
	end)

	it("lazy registration works with libuv.", function()
		mkdir("a")

		exec_lua([[
			seen_files = {
				["a/a/a"] = 0,
			}
			-- won't see any directories, a/a is root.
			changed = {
				["a/a/a"] = 0,
			}

			watcher = scratch_tree_watcher("a/a", 3, {
				new_file = function(path)
					seen_files[path] = seen_files[path] + 1
				end,
				new_dir = function(path)
					seen_dirs[path] = seen_dirs[path] + 1
				end,
				change_file = function(path)
					changed[path] = changed[path] + 1
				end
			}, {lazy=true, fs_event_providers = {libuv = true, autocmd = false} } )
		]])

		mkdir("a/a")
		touch("a/a/a")

		assert.are.same({
			{
				["a/a/a"] = 1,
			},
			{
				["a/a/a"] = 1,
			},
		}, exec_lua([[return {seen_files, changed}]]))
	end)

	it("lazy registration works with autocmd.", function()
		mkdir("a")

		exec_lua([[
			seen_files = {
				["a/a/a"] = 0,
			}
			-- won't see any directories, a/a is root.
			changed = {
				["a/a/a"] = 0,
			}

			watcher = scratch_tree_watcher("a/a", 3, {
				new_file = function(path)
					seen_files[path] = seen_files[path] + 1
				end,
				new_dir = function(path)
					seen_dirs[path] = seen_dirs[path] + 1
				end,
				change_file = function(path)
					changed[path] = changed[path] + 1
				end
			}, {lazy=true, fs_event_providers = {libuv = false, autocmd = true} } )
		]])

		edit("a/a/a")

		assert.are.same({
			{
				["a/a/a"] = 1,
			},
			{
				["a/a/a"] = 1,
			},
		}, exec_lua([[return {seen_files, changed}]]))
	end)
end)
