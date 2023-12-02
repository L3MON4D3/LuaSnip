local Path = require("luasnip.util.path")
local uv = vim.uv or vim.loop
local util = require("luasnip.util.util")
local log_tree = require("luasnip.util.log").new("tree-watcher")
local log_path = require("luasnip.util.log").new("path-watcher")
local log = require("luasnip.util.log").new("fs-watchers")

local M = {}

-- used by both watchers.
local callback_mt = {
	__index = function()
		return util.nop
	end,
}

--- @alias LuaSnip.FSWatcher.FSEventProviders
--- | '"autocmd"' Hook into BufWritePost to receive notifications on file-changes.
--- | '"libuv"' Register uv.fs_event to receive notifications on file-changes.

--- @alias LuaSnip.FSWatcher.Callback fun(full_path: string)

--- @class LuaSnip.FSWatcher.TreeCallbacks
--- @field new_file LuaSnip.FSWatcher.Callback?
--- @field new_dir LuaSnip.FSWatcher.Callback?
--- @field remove_file LuaSnip.FSWatcher.Callback?
--- @field remove_dir LuaSnip.FSWatcher.Callback?
--- @field remove_root LuaSnip.FSWatcher.Callback?
--- @field change_file LuaSnip.FSWatcher.Callback?
--- @field change_dir LuaSnip.FSWatcher.Callback?
--- The callbacks are called with the full path to the file/directory that is
--- affected.
--- Callbacks that are not set will be replaced by a nop.

--- @class LuaSnip.FSWatcher.PathCallbacks
--- @field add LuaSnip.FSWatcher.Callback?
--- @field remove LuaSnip.FSWatcher.Callback?
--- @field change LuaSnip.FSWatcher.Callback?
--- The callbacks are called with the full path to the file that path-watcher
--- is registered on.
--- Callbacks that are not set will be replaced by a nop.

--- @class LuaSnip.FSWatcher.Options
--- @field lazy boolean?
--- If set, the watcher will be initialized even if the root/watched path does
--- not yet exist, and start notifications once it is created.
--- @field fs_event_providers table<LuaSnip.FSWatcher.FSEventProviders, boolean>?
--- Which providers to use for receiving file-changes.

local function get_opts(opts)
	opts = opts or {}
	local lazy = vim.F.if_nil(opts.lazy, false)
	local fs_event_providers =
		vim.F.if_nil(opts.fs_event_providers, { autocmd = true, libuv = false })

	return lazy, fs_event_providers
end

-- plain list, don't use map-style table since we'll only need direct access to
-- a watcher when it is stopped, which seldomly happens (at least, compared to
-- how often it is iterated in the autocmd-callback).
M.autocmd_watchers = {}

vim.api.nvim_create_augroup("_luasnip_fs_watcher", {})
vim.api.nvim_create_autocmd({ "BufWritePost" }, {
	callback = function(args)
		log.debug("Received BufWritePost for file %s.", args.file)
		local realpath = Path.normalize(args.file)
		if not realpath then
			-- if nil, the path does not exist for some reason.
			log.info(
				"Registered BufWritePost with <afile> %s, but realpath does not exist. Aborting fs-watcher-notification.",
				args.file
			)
			return
		end
		log.debug(
			"Received update for file %s, using realpath %s.",
			args.file,
			realpath
		)

		-- remove stopped watchers.
		-- Does not really matter whether we do this before or after the
		-- callbacks, since stopped watchers already take care to not do
		-- callbacks.
		-- Doing this during the callback-invocations, however, would incur
		-- some more complexity since ipairs does not support removal of
		-- elements during the iteration.
		M.autocmd_watchers = vim.tbl_filter(function(watcher)
			-- this won't catch unstarted watchers, since they can't be in this
			-- list in the first place.
			return not watcher.stopped
		end, M.autocmd_watchers)

		for _, watcher in ipairs(M.autocmd_watchers) do
			watcher:BufWritePost_callback(realpath)
		end
	end,
	group = "_luasnip_fs_watcher",
})

-- similar autocmd_watchers, only this list contains watchers that should be
-- notified on a manual update (which right now is every watcher).
M.active_watchers = {}
function M.write_notify(realpath)
	M.active_watchers = vim.tbl_filter(function(watcher)
		-- this won't catch unstarted watchers, since they can't be in this
		-- list in the first place.
		return not watcher.stopped
	end, M.active_watchers)

	for _, watcher in ipairs(M.active_watchers) do
		watcher:BufWritePost_callback(realpath)
	end
end

--- @class LuaSnip.FSWatcher.Tree
--- @field root string
--- @field fs_event userdata
--- @field files table<string, boolean>
--- @field dir_watchers table<string, LuaSnip.FSWatcher.Tree>
--- @field removed boolean
--- @field stopped boolean
--- @field callbacks LuaSnip.FSWatcher.TreeCallbacks
--- @field depth number How deep the root should be monitored.
--- @field fs_event_providers table<LuaSnip.FSWatcher.FSEventProviders, boolean>
--- @field root_realpath string? Set as soon as the watcher is started.
local TreeWatcher = {}
local TreeWatcher_mt = {
	__index = TreeWatcher,
}

function TreeWatcher:stop()
	for _, child_watcher in ipairs(self.dir_watchers) do
		child_watcher:stop()
	end
	self:stop_self()
end

function TreeWatcher:stop_self()
	-- don't check which fs_event_providers were actually started, for both of
	-- these it should not matter if they weren't.
	self.stopped = true
	self.send_notifications = false

	self.fs_event:stop()
	-- will be removed from active_watchers/autocmd_watchers after the next event, but already won't receive it.
end

function TreeWatcher:fs_event_callback(err, relpath, events)
	if not self.send_notifications then
		-- abort if we should not send notifications anymore.
		return
	end
	vim.schedule_wrap(function()
		log_tree.debug(
			"raw: self.root: %s; err: %s; relpath: %s; change: %s; rename: %s",
			self.root,
			err,
			relpath,
			events.change,
			events.rename
		)
		local full_path = Path.join(self.root, relpath)
		local path_stat = uv.fs_stat(full_path)

		-- try to figure out what happened in the directory.
		if events.rename then
			if not uv.fs_stat(self.root) then
				self:remove_root()
				return
			end
			if not path_stat then
				self:remove_child(relpath, full_path)
				return
			end

			local f_type
			-- if there is a link to a directory, we are notified on changes!!
			if path_stat.type == "link" then
				f_type = uv.fs_stat(uv.fs_realpath(full_path))
			else
				f_type = path_stat.type
			end

			if f_type == "file" then
				self:new_file(relpath, full_path)
				return
			elseif f_type == "directory" then
				self:new_dir(relpath, full_path)
				return
			end
		elseif events.change then
			self:change_child(relpath, full_path)
		end
	end)()
end

-- May not recognize child correctly if there are symlinks on the path from the
-- child to the directory-root.
-- Should be fine, especially since, I think, fs_event can recognize those
-- correctly, which means that this is an issue only very seldomly.
function TreeWatcher:BufWritePost_callback(realpath)
	if not self.send_notifications then
		return
	end

	if realpath:sub(1, #self.realpath_root) ~= self.realpath_root then
		-- not inside this root.
		return
	end

	-- `#self.realpath_root+2`: remove root and path-separator.
	local root_relative_components =
		Path.components(realpath:sub(#self.realpath_root + 2))
	local rel = root_relative_components[1]
	if #root_relative_components == 1 then
		-- wrote file.
		-- either new, or changed.
		if self.files[rel] then
			-- use regular root for notifications!
			self:change_file(rel, Path.join(self.root, rel))
		else
			self:new_file(rel, Path.join(self.root, rel))
		end
	else
		if self.dir_watchers[rel] then
			if #root_relative_components == 2 then
				-- only notify if the changed file is immediately in the
				-- directory we're watching!
				-- I think this is the behaviour of fs_event, and logically
				-- makes sense.
				self:change_dir(rel, Path.join(self.root, rel))
			end
		else
			-- does nothing if the directory already exists.
			self:new_dir(rel, Path.join(self.root, rel))
		end
	end
end

function TreeWatcher:start()
	if self.depth == 0 then
		-- don't watch children for 0-depth.
		return
	end

	if self.stopped then
		-- stopping overrides and prevents starting.
		return
	end

	self.send_notifications = true

	if self.fs_event_providers.libuv then
		-- does not work on nfs-drive, at least if it's edited from another
		-- machine.
		local success, err = self.fs_event:start(
			self.root,
			{},
			function(err, relpath, events)
				self:fs_event_callback(err, relpath, events)
			end
		)

		if not success then
			log_tree.error(
				"Could not start libuv-monitor for path %s due to error %s",
				self.path,
				err
			)
		else
			log_tree.info(
				"Monitoring root-directory %s with libuv-monitor.",
				self.root
			)
		end
	end

	-- needed by BufWritePost-callback.
	self.realpath_root = Path.normalize(self.root)

	if self.fs_event_providers.autocmd then
		if self.realpath_root then
			-- receive notifications on BufWritePost.
			table.insert(M.autocmd_watchers, self)
			log_tree.info(
				"Monitoring root-directory %s with autocmd-monitor.",
				self.root
			)
		else
			log_tree.error(
				"Could not resolve realpath for root %s, not enabling autocmd-monitor",
				self.root
			)
		end
	end

	if self.realpath_root then
		table.insert(M.active_watchers, self)
	end

	-- do initial scan after starting the watcher.
	-- Scanning first, and then starting the watcher leaves a period of time
	-- where a new file may be created (after scanning, before watching), where
	-- we wont know about it.
	-- If I understand the uv-eventloop correctly, this function, `new`, will
	-- be executed completely before a callback is called, so self.files and
	-- self.dir_watchers should be populated correctly when a callback is
	-- received, even if it was received before all directories/files were
	-- added.
	-- This difference can be observed, at least on my machine, by watching a
	-- directory A, and then creating a nested directory B, and children for it
	-- in one command, ie. `mkdir -p A/B/{1,2,3,4,5,6,7,8,9}`.
	-- If the callback is registered after the scan, the latter directories
	-- (ie. 4-9) did not show up, whereas everything did work correctly if the
	-- watcher was activated before the scan.
	-- (almost everything, one directory was included in the initial scan and
	-- the watch-event, but that seems okay for our purposes)
	local files, dirs = Path.scandir(self.root)
	for _, file in ipairs(files) do
		local relpath = file:sub(#self.root + 2)
		self:new_file(relpath, file)
	end
	for _, dir in ipairs(dirs) do
		local relpath = dir:sub(#self.root + 2)
		self:new_dir(relpath, dir)
	end
end

-- these functions maintain our logical view of the directory, and call
-- callbacks when we detect a change.
function TreeWatcher:new_file(rel, full)
	if self.files[rel] then
		-- already added
		return
	end

	log_tree.debug("new file %s %s", rel, full)
	self.files[rel] = true
	self.callbacks.new_file(full)
end
function TreeWatcher:new_dir(rel, full)
	if self.dir_watchers[rel] then
		-- already added
		return
	end

	log_tree.debug("new dir %s %s", rel, full)
	-- first do callback for this directory, then look into (and potentially do
	-- callbacks for) children.
	self.callbacks.new_dir(full)
	-- directory exists => don't need to set lazy.
	-- inherit fs_event_providers.
	self.dir_watchers[rel] = M.tree(
		full,
		self.depth - 1,
		self.callbacks,
		{ lazy = false, fs_event_providers = self.fs_event_providers }
	)
end

function TreeWatcher:change_file(rel, full)
	log_tree.debug("changed file %s %s", rel, full)
	self.callbacks.change_file(full)
end
function TreeWatcher:change_dir(rel, full)
	log_tree.debug("changed dir %s %s", rel, full)
	self.callbacks.change_dir(full)
end
function TreeWatcher:change_child(rel, full)
	if self.dir_watchers[rel] then
		self:change_dir(rel, full)
	elseif self.files[rel] then
		self:change_file(rel, full)
	end
end

function TreeWatcher:remove_child(rel, full)
	if self.dir_watchers[rel] then
		log_tree.debug("removing dir %s %s", rel, full)
		-- should have been stopped by the watcher for the child, or it was not
		-- even started due to depth.
		self.dir_watchers[rel]:remove_root()
		self.dir_watchers[rel] = nil

		self.callbacks.remove_dir(full)
	elseif self.files[rel] then
		log_tree.debug("removing file %s %s", rel, full)
		self.files[rel] = nil

		self.callbacks.remove_file(full)
	end
end

function TreeWatcher:remove_root()
	if self.removed then
		-- already removed
		return
	end
	log_tree.debug("removing root %s", self.root)
	self.removed = true
	-- stop own, children should have handled themselves, if they are watched
	-- (and we don't need to do anything for unwatched children).
	self:stop_self()

	-- removing entries (set them to nil) is apparently fine when iterating via
	-- pairs.
	for relpath, _ in pairs(self.files) do
		local child_full = Path.join(self.root, relpath)
		self:remove_child(relpath, child_full)
	end
	for relpath, _ in pairs(self.dir_watchers) do
		local child_full = Path.join(self.root, relpath)
		self:remove_child(relpath, child_full)
	end

	self.callbacks.remove_root(self.root)
end

--- Set up new watcher for a tree of files and directories.
--- @param root string Absolute path to the root.
--- @param depth number The depth up to which to monitor. 1 means that the
---                     immediate children will be monitored, 2 includes their
---                     children, and so on.
--- @param callbacks LuaSnip.FSWatcher.TreeCallbacks The callbacks to use for this watcher.
--- @param opts LuaSnip.FSWatcher.Options Options, described in their class.
--- @return LuaSnip.FSWatcher.Tree
function M.tree(root, depth, callbacks, opts)
	local lazy, fs_event_providers = get_opts(opts)

	-- do nothing on missing callback.
	callbacks = setmetatable(callbacks or {}, callback_mt)

	local o = setmetatable({
		root = root,
		fs_event = uv.new_fs_event(),
		files = {},
		dir_watchers = {},
		-- removed: have not yet triggered the removed-callback.
		removed = false,

		-- track whether the watcher was stopped at some point, and if it as,
		-- don't allow it to start again.
		stopped = false,
		-- whether notifications should be sent.
		-- Modified by start/stop, wait for start to send any => start out as
		-- false.
		send_notifications = false,

		callbacks = callbacks,
		depth = depth,
		fs_event_providers = fs_event_providers,
	}, TreeWatcher_mt)

	-- if the path does not yet exist, set watcher up s.t. it will start
	-- watching when the directory is created.
	if not uv.fs_stat(root) and lazy then
		-- root does not yet exist, need to create a watcher that notifies us
		-- of its creation.
		local parent_path = Path.parent(root)
		if not parent_path then
			error(("Could not find parent-path for %s"):format(root))
		end

		log_tree.info(
			"Path %s does not exist yet, watching %s for creation.",
			root,
			parent_path
		)

		local parent_watcher
		parent_watcher = M.tree(parent_path, 1, {
			new_dir = function(full)
				if full == root then
					o:start()
					-- directory was created, stop watching.
					parent_watcher:stop_self()
				end
			end,
			-- use same providers.
		}, { lazy = true, fs_event_providers = fs_event_providers })
	else
		o:start()
	end

	return o
end

--- @class LuaSnip.FSWatcher.Path
--- @field private path string
--- @field private fs_event userdata
--- @field private removed boolean
--- @field private stopped boolean
--- @field private send_notifications boolean
--- @field private callbacks LuaSnip.FSWatcher.TreeCallbacks
--- @field private fs_event_providers table<LuaSnip.FSWatcher.FSEventProviders, boolean>
--- @field private realpath string? Set as soon as the watcher is started.
local PathWatcher = {}

local PathWatcher_mt = {
	__index = PathWatcher,
}

function PathWatcher:change(full)
	log_path.info("detected change at path %s", full)
	if self.removed then
		-- this is certainly unexpected.
		log_path.warn(
			"PathWatcher at %s detected change, but path does not exist logically. Not triggering callback.",
			full
		)
	else
		self.callbacks.change(self.path)
	end
end

function PathWatcher:add()
	if not self.removed then
		-- already added
		return
	end
	log_path.info("adding path %s", self.path)
	self.removed = false

	self.callbacks.add(self.path)
end
function PathWatcher:remove()
	if self.removed then
		-- already removed
		return
	end
	log_path.debug("removing path %s", self.path)
	log_path.info("path %s was removed, stopping watcher.", self.path)

	self.removed = true

	self.callbacks.remove(self.path)

	-- Would have to re-register for new file to receive new notifications.
	self:stop()
end

function PathWatcher:fs_event_callback(err, relpath, events)
	if not self.send_notifications then
		return
	end

	vim.schedule_wrap(function()
		log_path.debug(
			"raw: path: %s; err: %s; relpath: %s; change: %s; rename: %s",
			self.path,
			err,
			relpath,
			events.change,
			events.rename
		)

		if events.rename then
			if not uv.fs_stat(self.path) then
				self:remove()
			else
				self:add()
			end
		elseif events.change then
			self:change()
		end
	end)()
end

function PathWatcher:BufWritePost_callback(realpath)
	if not self.send_notifications then
		return
	end

	if realpath == self.realpath then
		-- notify using passed path, not realpath.
		self:change(self.path)
	end
end

function PathWatcher:start()
	if self.stopped then
		-- stop() prevents start.
		return
	end
	self.send_notifications = true

	if self.fs_event_providers.libuv then
		-- does not work on nfs-drive, at least if it's edited from another
		-- machine.
		local success, err = self.fs_event:start(
			self.path,
			{},
			function(err, relpath, events)
				self:fs_event_callback(err, relpath, events)
			end
		)

		if not success then
			log_path.error(
				"Could not start libuv-monitor for file %s due to error %s",
				self.path,
				err
			)
		else
			log_path.info("Monitoring file %s with libuv-monitor.", self.path)
		end
	end

	local realpath = Path.normalize(self.path)

	if self.fs_event_providers.autocmd then
		if realpath then
			self.realpath = realpath

			-- path exists, add file-monitor.
			table.insert(M.autocmd_watchers, self)
			log_path.info("Monitoring file %s with autocmd-monitor.", self.path)
		else
			log_path.error(
				"Could not resolve realpath for file %s, not enabling BufWritePost-monitor",
				self.path
			)
		end
	end

	if realpath then
		table.insert(M.active_watchers, self)
	end

	if realpath then
		-- path exists, notify.
		self:add()
		-- no else, never added the path, never call remove.
	end
end

function PathWatcher:stop()
	-- don't check which fs_event_providers were actually started, for both of
	-- these it should not matter if they weren't.
	self.stopped = true
	self.send_notifications = false

	self.fs_event:stop()
end

--- Set up new watcher on a single path only.
--- @param path string Absolute path to the root.
--- @param callbacks LuaSnip.FSWatcher.PathCallbacks The callbacks to use for this watcher.
--- @param opts LuaSnip.FSWatcher.Options? Options, described in their class.
--- @return LuaSnip.FSWatcher.Path
function M.path(path, callbacks, opts)
	local lazy, fs_event_providers = get_opts(opts)

	-- do nothing on missing callback.
	callbacks = setmetatable(callbacks or {}, callback_mt)

	--- @as LuaSnip.FSWatcher.Path
	local o = setmetatable({
		path = path,
		fs_event = uv.new_fs_event(),
		-- Don't send an initial remove-callback if the path does not yet
		-- exist.
		-- Always send add first, or send nothing.
		removed = true,
		-- these two are just like in TreeWatcher.
		stopped = false,
		-- wait for `start()` to send notifications.
		send_notifications = false,
		callbacks = callbacks,
		fs_event_providers = fs_event_providers,
	}, PathWatcher_mt)

	-- if the path does not yet exist, set watcher up s.t. it will start
	-- watching when the directory is created.
	if not uv.fs_stat(path) and lazy then
		-- root does not yet exist, need to create a watcher that notifies us
		-- of its creation.
		local parent_path = Path.parent(path)
		if not parent_path then
			error(("Could not find parent-path for %s"):format(path))
		end

		log_path.info(
			"Path %s does not exist yet, watching %s for creation.",
			path,
			parent_path
		)

		local parent_watcher
		parent_watcher = M.tree(parent_path, 1, {
			-- in path_watcher, watch for new file.
			new_file = function(full)
				log_path.info("Path: %s %s", full, path)
				if full == path then
					o:start()
					-- directory was created, stop watching.
					parent_watcher:stop_self()
				end
			end,
		}, { lazy = true, fs_event_providers = fs_event_providers })
	else
		o:start()
	end

	return o
end

return M
