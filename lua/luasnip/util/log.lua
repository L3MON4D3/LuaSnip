local util = require("luasnip.util.util")
local tbl = require("luasnip.util.table")

-- older neovim-versions (even 0.7.2) do not have stdpath("log").
local logpath_ok, logpath = pcall(vim.fn.stdpath, "log")
if not logpath_ok then
	logpath = vim.fn.stdpath("cache")
end

local override_logpath = os.getenv("LUASNIP_OVERRIDE_LOGPATH")
if override_logpath then
	logpath = override_logpath
end

-- just to be sure this dir exists.
-- 448 = 0700
vim.loop.fs_mkdir(logpath, 448)

local log_location = logpath .. "/luasnip.log"
local log_old_location = logpath .. "/luasnip.log.old"

local luasnip_log_fd = vim.loop.fs_open(
	log_location,
	-- only append.
	"a",
	-- 420 = 0644
	420
)

local function log_line_append(msg)
	msg = msg:gsub("\n", "\n      | ")
	vim.loop.fs_write(luasnip_log_fd, msg .. "\n")
end

if not luasnip_log_fd then
	-- print a warning
	print(
		("LuaSnip: could not open log at %s. Not logging for this session."):format(
			log_location
		)
	)
	-- make log_line_append do nothing.
	log_line_append = util.nop
else
	-- if log_fd found, check if log should be rotated.
	local logsize = vim.loop.fs_fstat(luasnip_log_fd).size
	if logsize > 10 * 2 ^ 20 then
		-- logsize > 10MiB:
		-- move log -> old log, start new log.
		vim.loop.fs_rename(log_location, log_old_location)
		luasnip_log_fd = vim.loop.fs_open(
			log_location,
			-- only append.
			"a",
			-- 420 = 0644
			420
		)
	end
end

local M = {}

--- The file path we're currently logging into.
function M.log_location()
	return logpath
end
--- Time formatting for logs. Defaults to '%X'.
M.time_fmt = "%X"

local function make_log_level(level)
	return function(msg)
		log_line_append(
			string.format("%s | %s | %s", level, os.date(M.time_fmt), msg)
		)
	end
end

local log = {
	error = make_log_level("ERROR"),
	warn = make_log_level("WARN"),
	info = make_log_level("INFO"),
	debug = make_log_level("DEBUG"),
}

-- functions copied directly by deepcopy.
-- will be initialized later on, by set_loglevel.
local effective_log

-- levels sorted by importance, descending.
local loglevels = { "error", "warn", "info", "debug" }

-- special key none disable all logging.
function M.set_loglevel(target_level)
	local target_level_indx = util.indx_of(loglevels, target_level)
	if target_level == "none" then
		target_level_indx = 0
	end

	assert(target_level_indx ~= nil, "invalid level!")

	-- reset effective loglevels, set those with importance higher than
	-- target_level, disable (nop) those with lower.
	effective_log = {}
	for i = 1, target_level_indx do
		effective_log[loglevels[i]] = log[loglevels[i]]
	end
	for i = target_level_indx + 1, #loglevels do
		effective_log[loglevels[i]] = util.nop
	end
end

local describe_key = {}

local function mk_describe(f)
	local wrapped_f = function(self)
		return f(unpack(self.args))
	end
	return function(...)
		return {
			args = { ... },
			get = wrapped_f,
			-- we want to be able to uniquely identify describe-objects, and the
			-- simplest way (I think) is to set a unique key that is not known,
			-- or even better, accessible by other modules.
			[describe_key] = true,
		}
	end
end
local function is_describe(t)
	return type(t) == "table" and t[describe_key] ~= nil
end

M.describe = {
	node_buftext = mk_describe(function(node)
		local from, to = node:get_buf_position()
		return vim.inspect(
			vim.api.nvim_buf_get_text(0, from[1], from[2], to[1], to[2], {})
		)
	end),
	node = mk_describe(function(node)
		if not node.parent then
			return ("snippet[trig: %s]"):format(node.trigger)
		else
			local snip_id = node.parent.snippet.trigger
			-- render node readably.
			local node_id = ""
			if node.key then
				node_id = "key: " .. node.key
			elseif node.absolute_insert_position then
				node_id = "insert_pos: "
					.. vim.inspect(node.absolute_insert_position)
			else
				node_id = "pos: " .. vim.inspect(node.absolute_position)
			end
			return ("node[%s, snippet: `%s`]"):format(node_id, snip_id)
		end
	end),
	inspect = mk_describe(function(t, inspect_opts)
		return vim.inspect(t, inspect_opts or {})
	end),
	traceback = mk_describe(function()
		-- get position where log.debug is called with describe-object.
		return debug.traceback("", 3)
	end),
}

local function readable_format(msg, ...)
	local args = tbl.pack(...)
	for i, arg in ipairs(args) do
		if is_describe(arg) then
			args[i] = arg:get()
		end
	end
	return msg:format(tbl.unpack(args))
end

function M.new(module_name)
	local module_log = {}
	for name, _ in pairs(log) do
		module_log[name] = function(msg, ...)
			-- don't immediately get the referenced function, we'd like to
			-- allow changing the loglevel on-the-fly.

			-- also: make sure that whatever code called for logging does not
			-- cause an error.
			local ok, fmt_msg = pcall(readable_format, msg, ...)
			if not ok then
				effective_log.error(
					('log: error while formatting or writing message "%s": %s'):format(
						msg,
						fmt_msg
					)
				)
			end

			effective_log[name](module_name .. ": " .. fmt_msg)
		end
	end
	return module_log
end

function M.open()
	vim.cmd(("tabnew %s"):format(log_location))
end

-- to verify log is working.
function M.ping()
	log_line_append(("PONG  | pong! (%s)"):format(os.date()))
end

-- set default-loglevel.
M.set_loglevel("warn")

return M
