---@alias LuaSnip.Cursor {[1]: number, [2]: number}

---@class LuaSnip.MatchRegion 0-based region within a single line
---@field row integer 0-based row
---@field col_range { [1]: integer, [2]: integer } 0-based column range, from-in, to-exclusive

---@alias LuaSnip.BytecolBufferPosition [integer, integer] Specifies a position
---in a buffer, or some other collection of lines.
---(0,0) is the first line, first character, and the column-position is
---specified in bytes, not visual columns (there are characters that are
---visually one column, but occupy several bytes).

---@class LuaSnip.BufferRegion 0-based region in a buffer.
---@field from LuaSnip.BytecolBufferPosition Starting position, included.
---@field to LuaSnip.BytecolBufferPosition Ending position, excluded.
