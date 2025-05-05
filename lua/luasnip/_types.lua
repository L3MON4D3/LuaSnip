---@alias LuaSnip.Cursor {[1]: number, [2]: number}

---@alias LuaSnip.ApiPosition {[1]: number, [2]: number} 0,0-based position,
---relative to some other position, or the beginning of the buffer. The
---column-number is given in bytes, not visual columns.

---@class LuaSnip.MatchRegion 0-based region
---@field row integer 0-based row
---@field col_range { [1]: integer, [2]: integer } 0-based column range, from-in, to-exclusive

---@alias LuaSnip.Addable table
---Anything that can be passed to ls.add_snippets().
