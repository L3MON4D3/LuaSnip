---@alias LuaSnip.Cursor {[1]: number, [2]: number}

---@class LuaSnip.MatchRegion 0-based region
---@field row integer 0-based row
---@field col_range { [1]: integer, [2]: integer } 0-based column range, from-in, to-exclusive

---@alias LuaSnip.Addable table
---Anything that can be passed to ls.add_snippets().
