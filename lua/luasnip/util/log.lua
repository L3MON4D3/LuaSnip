local util = require("luasnip.util.util")

-- older neovim-versions (even 0.7.2) do not have stdpath("log").
local logpath_ok, logpath = pcall(vim.fn.stdpath, "log")
if not logpath_ok then
	logpath = vim.fn.stdpath("cache")
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

local log = {
	error = function(msg)
		log_line_append("ERROR | " .. msg)
	end,
	warn = function(msg)
		log_line_append("WARN  | " .. msg)
	end,
	info = function(msg)
		log_line_append("INFO  | " .. msg)
	end,
	debug = function(msg)
		log_line_append("DEBUG | " .. msg)
	end,
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

function M.new(module_name)
	local module_log = {}
	for name, _ in pairs(log) do
		module_log[name] = function(msg, ...)
			-- don't immediately get the referenced function, we'd like to
			-- allow changing the loglevel on-the-fly.
			effective_log[name](module_name .. ": " .. msg:format(...))
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
