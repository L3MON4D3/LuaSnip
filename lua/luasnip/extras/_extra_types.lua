---@class LuaSnip.extra.MatchTSNodeOpts Passed in by the user, describes how to
---select a node from the tree via a query and captures.
---@field query? string A query, as text
---@field query_name? string The name of a query (passed to `vim.treesitter.query.get`).
---@field query_lang string The language of the query.
---@field select? LuaSnip.extra.BuiltinMatchSelector|LuaSnip.extra.MatchSelector
---@field match_captures? string|string[]

---@class LuaSnip.extra.MatchedTSNodeInfo
---@field capture_name string
---@field node TSNode

---@alias LuaSnip.extra.BuiltinMatchSelector
---| '"any"' # The default selector, selects the first match but not return all captures
---| '"shortest"' # Selects the shortest match, return all captures too
---| '"longest"' # Selects the longest match, return all captures too

---Call record repeatedly to record all matches/nodes, retrieve once there are no more matches
---@class LuaSnip.extra.MatchSelector
---@field record fun(ts_match: TSMatch?, node: TSNode): boolean return true if recording can be aborted
---                                                             (because the best match has been found)
---@field retrieve fun(): TSMatch?,TSNode? return the best match, as determined by this selector.

---@alias LuaSnip.extra.MatchTSNodeFunc fun(parser: LuaSnip.extra.TSParser, cursor: LuaSnip.Cursor): LuaSnip.extra.NamedTSMatch?,TSNode?

---@alias LuaSnip.extra.NamedTSMatch table<string,TSNode>
