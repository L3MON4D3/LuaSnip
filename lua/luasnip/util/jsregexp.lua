local Path = require("luasnip.util.path")

-- neovim-loader does not handle module-names with dots correctly, so for
-- jsregexp-0.0.6, the call to require("jsregexp.core") in jsregexp.lua errors
-- even if the library is in rtp.
-- Resolve path to jsregexp.so manually, and loadlib it in preload (and remove
-- preload after requires are done and have failed/worked).

-- omit "@".
local this_file = debug.getinfo(1).source:sub(2)
local repo_dir = vim.fn.fnamemodify(this_file, ":h:h:h:h")
local jsregexp_core_path = Path.join(repo_dir, "deps", "luasnip-jsregexp.so")

-- rather gracefully, if the path does not exist, or loadlib can't do its job
-- for some other reason, the preload will be set to nil, ie not be set.
--
-- This means we don't hinder a regularly installed 0.0.6-jsregexp-library,
-- since its `require("jsregexp.core")` will be unaffected.
package.preload["jsregexp.core"] =
	package.loadlib(jsregexp_core_path, "luaopen_jsregexp_core")

-- jsregexp: first try loading the version installed by luasnip, then global ones.
local jsregexp_ok, jsregexp = pcall(require, "luasnip-jsregexp")
if not jsregexp_ok then
	jsregexp_ok, jsregexp = pcall(require, "jsregexp")
end

-- don't want to affect other requires.
package.preload["jsregexp.core"] = nil

if not jsregexp_ok then
	return false
end

-- detect version, and return compile-function.
-- 0.0.6-compile_safe and 0.0.5-compile behave the same, ie. nil, err on error.
if jsregexp.compile_safe then
	return jsregexp.compile_safe
else
	return jsregexp.compile
end
