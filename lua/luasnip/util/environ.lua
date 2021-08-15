local util = require("luasnip.util.util")

local eager_vars = {
	["TM_CURRENT_LINE"] = true,
	["TM_CURRENT_WORD"] = true,
	["TM_LINE_INDEX"] = true,
	["TM_LINE_NUMBER"] = true,
}

-- These are the vars that have to be populated once the snippet starts to avoid any issue
local function _fill_eager_vars(env)
	local cur = util.get_cursor_0ind()
	env.TM_CURRENT_LINE = vim.api.nvim_buf_get_lines(
		0,
		cur[1],
		cur[1] + 1,
		false
	)[1]
	env.TM_CURRENT_WORD = util.word_under_cursor(cur, env.TM_CURRENT_LINE)
	env.TM_LINE_INDEX = tostring(cur[1])
	env.TM_LINE_NUMBER = tostring(cur[1] + 1)
end

local lazy_vars = {}

local Environ = {}
function Environ:new(o)
	o = o or {}
	setmetatable(o, self)
	_fill_eager_vars(o)
	return o
end

function Environ:__index(key)
	local v = lazy_vars[key]()
	rawset(self, key, v)
	return v
end

-- Variables defined in https://code.visualstudio.com/docs/editor/userdefinedsnippets#_variables

-- Inherited from TextMate
function lazy_vars.TM_FILENAME_BASE()
	return vim.fn.expand("%:t:s?\\.[^\\.]\\+$??")
end

function lazy_vars.TM_DIRECTORY()
	return vim.fn.expand("%:p:h")
end
function lazy_vars.TM_FILEPATH()
	return vim.fn.expand("%:p")
end

function lazy_vars.TM_SELECTED_TEXT()
	util.get_selection(util.TM_SELECT)
end

-- Vscode only

function lazy_vars.CLIPBOARD() -- The contents of your clipboard
	return vim.fn.getreg('"', 1, true)
end

--[[ This ones will probably need some LSP involvment
function lazy_vars.RELATIVE_FILEPATH() -- The relative (to the opened workspace or folder) file path of the current document
end
function lazy_vars.WORKSPACE_NAME() -- The name of the opened workspace or folder
end
function lazy_vars.WORKSPACE_FOLDER() -- The path of the opened workspace or folder
end
 ]]

-- DateTime Related
function lazy_vars.CURRENT_YEAR()
	return os.date("%Y")
end
function lazy_vars.CURRENT_YEAR_SHORT()
	return os.date("%y")
end
function lazy_vars.CURRENT_MONTH()
	return os.date("%m")
end
function lazy_vars.CURRENT_MONTH_NAME()
	return os.date("%B")
end
function lazy_vars.CURRENT_MONTH_NAME_SHORT()
	return os.date("%b")
end
function lazy_vars.CURRENT_DATE()
	return os.date("%d")
end
function lazy_vars.CURRENT_DAY_NAME()
	return os.date("%A")
end
function lazy_vars.CURRENT_DAY_NAME_SHORT()
	return os.date("%a")
end
function lazy_vars.CURRENT_HOUR()
	return os.date("%H")
end
function lazy_vars.CURRENT_MINUTE()
	return os.date("%M")
end
function lazy_vars.CURRENT_SECOND()
	return os.date("%S")
end
function lazy_vars.CURRENT_SECONDS_UNIX()
	return tostring(os.time())
end

-- For inserting random values

math.randomseed(os.time())

function lazy_vars.RANDOM()
	return string.format("%06d", math.random(999999))
end

function lazy_vars.RANDOM_HEX()
	return string.format("%06x", math.random(16777216)) --16^6
end

function lazy_vars.UUID()
	local random = math.random
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	local out
	local function subs(c)
		local v = (((c == "x") and random(0, 15)) or random(8, 11))
		return string.format("%x", v)
	end
	out = template:gsub("[xy]", subs)
	return out
end

function lazy_vars.LINE_COMMENT()
	return util.buffer_comment_chars()[1]
end
function lazy_vars.BLOCK_COMMENT_START()
	return util.buffer_comment_chars()[2]
end
function lazy_vars.BLOCK_COMMENT_END()
	return util.buffer_comment_chars()[3]
end

-- Extra vars
function lazy_vars.SELECT_RAW()
	util.get_selection(util.SELECT_RAW)
end

function lazy_vars.SELECT_DEDENT()
	util.get_selection(util.SELECT_DEDENT)
end

function Environ.is_valid_var(key)
	return (eager_vars[key] or lazy_vars[key]) and true
end

return Environ
