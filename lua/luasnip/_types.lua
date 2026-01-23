---@class LuaSnip.Pos00 A [row, col] position (e.g. in a buffer), (0,0)-indexed.
---@field [1] integer
---@field [2] integer

---@alias LuaSnip.Cursor {[1]: number, [2]: number}

---@class LuaSnip.Region00InLine 0-based region within a single line
---@field row integer 0-based row
---@field col_range { [1]: integer, [2]: integer } 0-based column range, from-in, to-exclusive

--- A raw (byte) [row, col] position in a buffer, (0,0)-indexed.
--- Specifies a position in a buffer, or some other collection of lines. (0,0) is
--- the first line, first character, and the column-position is specified in
--- bytes, not visual columns (there are characters that are visually one column,
--- but occupy several bytes).
---@class LuaSnip.RawPos00
---@field [1] integer
---@field [2] integer

--- 0-based region (end column excluded) in a buffer.
---@class LuaSnip.RawRegion00
---@field from LuaSnip.RawPos00 Starting position, included.
---@field to LuaSnip.RawPos00 Ending position, excluded.
