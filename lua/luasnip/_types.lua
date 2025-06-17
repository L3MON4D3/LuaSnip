---@alias LuaSnip.Cursor {[1]: number, [2]: number}

---@class LuaSnip.MatchRegion 0-based region within a single line
---@field row integer 0-based row
---@field col_range { [1]: integer, [2]: integer } 0-based column range, from-in, to-exclusive

---@class LuaSnip.BufferRegion 0-based region in a buffer.
---@field from [integer, integer] row,col-tuple, usually considered within the
---range.
---@field to [integer, integer] row,col, usually considered one column beyond
---the range.

---@alias LuaSnip.Addable table
---Anything that can be passed to ls.add_snippets().

-- very approximate classes, for now.
---@alias LuaSnip.Snippet table
---@alias LuaSnip.Node table
