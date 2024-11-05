-- insert operations into typeahead buffer in a controlled manner.
-- We want to follow these guidelines:
-- * maintain order of luasnip-operations. Example:
--   `ls.jump() ls.jump()`, the first jump is completely executed, and only
--   then the second jump is.
-- * insert our operations before other typeahead.
--   This is to behave correctly in a macro: IIUC the complete macro is written
--   into typeahead, so if our operations are appended, we will jump way later
--   than in the actual recorded "session", and input won't end up where it
--   belongs.
--
-- We will achieve these goals by only ever having one operation in the
-- typeahead, and once it is finished it calls a callback that will insert any
-- other keys that were requested to be executed.
--
-- This scheme is inspired by @hrsh7th's work in nvim-cmp.
local util = require("luasnip.util.util")

local M = {}

local current_id = 0
local executing_id = nil

-- contains functions which take exactly one argument, the id.
local enqueued_actions = {}

local function _feedkeys_insert(id, keys)
	executing_id = id
	vim.api.nvim_feedkeys(
		vim.api.nvim_replace_termcodes(
			keys
				.. "<cmd>lua require('luasnip.util.feedkeys').confirm("
				.. id
				.. ")<cr>",
			true,
			false,
			true
		),
		-- folds are opened manually now, no need to pass t.
		-- n prevents langmap from interfering.
		"ni",
		true
	)
end

local function enqueue_action(fn)
	-- get unique id and increment global.
	local keys_id = current_id
	current_id = current_id + 1

	-- if there is nothing from luasnip currently executing, we may just insert
	-- into the typeahead
	if executing_id == nil then
		fn(keys_id)
	else
		enqueued_actions[keys_id] = fn
	end
end

function M.feedkeys_insert(keys)
	enqueue_action(function(id)
		_feedkeys_insert(id, keys)
	end)
end

-- pos: (0,0)-indexed.
local function cursor_set_keys(pos, before)
	if before then
		if pos[2] == 0 then
			pos[1] = pos[1] - 1
			-- pos2 is set to last columnt of previous line.
			-- # counts bytes, but win_set_cursor expects bytes, so all's good.
			pos[2] =
				#vim.api.nvim_buf_get_lines(0, pos[1], pos[1] + 1, false)[1]
		else
			pos[2] = pos[2] - 1
		end
	end

	return "<cmd>lua vim.api.nvim_win_set_cursor(0,{"
		-- +1, win_set_cursor starts at 1.
		.. pos[1] + 1
		.. ","
		-- -1 works for multibyte because of rounding, apparently.
		.. pos[2]
		.. "})"
		.. "<cr><cmd>:silent! foldopen!<cr>"
end

function M.select_range(b, e)
	enqueue_action(function(id)
		-- stylua: ignore
		_feedkeys_insert(id,
			-- this esc -> movement sometimes leads to a slight flicker
			-- TODO: look into preventing that reliably.
			-- Go into visual, then place endpoints.
			-- This is to allow us to place the cursor on the \n of a line.
			-- see #1158
			"<esc>"
			-- open folds that contain this selection.
			-- we assume that the selection is contained in at most one fold, and
			-- that that fold covers b.
			-- if we open the fold while visual is active, the selection will be
			-- wrong, so this is necessary before we enter VISUAL.
			.. cursor_set_keys(b)
			-- start visual highlight and move to b again.
			-- since we are now in visual, this might actually move the cursor.
			.. "v"
			.. cursor_set_keys(b)
			-- swap to other end of selection, and move it to e.
			.. "o"
			.. (vim.o.selection == "exclusive" and
				cursor_set_keys(e) or
				-- set before
				cursor_set_keys(e, true))
			.. "o<C-G><C-r>_" )
	end)
end

-- move the cursor to a position and enter insert-mode (or stay in it).
function M.insert_at(pos)
	enqueue_action(function(id)
		-- if current and target mode is INSERT, there's no reason to leave it.
		if vim.fn.mode() == "i" then
			-- can skip feedkeys here, we can complete this command from lua.
			-- Just have to make sure to call confirm afterward, since there
			-- may be more actions enqueued.
			-- We don't have to set the executing_id, since there's no way
			-- enqueue_action could be called before `confirm`.
			util.set_cursor_0ind(pos)
			M.confirm(id)
		else
			-- mode might be VISUAL or something else => <Esc> to know we're in NORMAL.
			_feedkeys_insert(id, "<Esc>i" .. cursor_set_keys(pos))
		end
	end)
end

function M.confirm(id)
	executing_id = nil

	if enqueued_actions[id + 1] then
		enqueued_actions[id + 1](id + 1)
		enqueued_actions[id + 1] = nil
	end
end

return M
