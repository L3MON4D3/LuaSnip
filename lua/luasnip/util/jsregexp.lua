local Path = require("luasnip.util.path")
local log = require("luasnip.util.log").new("jsregexp-wrapper")

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
if jsregexp_ok then
	log.debug("Loaded luasnip-installed jsregexp.")
else
	jsregexp_ok, jsregexp = pcall(require, "jsregexp")
	if jsregexp_ok then
		log.debug("Loaded jsregexp from LUAPATH.")
	end
end

-- don't want to affect other requires.
package.preload["jsregexp.core"] = nil

if not jsregexp_ok then
	log.info("Could not load jsregexp.")
	return false
end

-- if both exist, compile_safe is (nil, err) on error, otherwise compile has
-- this (desired!) behaviour.
local compile = nil
if jsregexp.compile_safe then
	compile = jsregexp.compile_safe
	log.debug("Using `compile_safe`.")
else
	compile = jsregexp.compile
	log.debug("Using `compile`.")
end

-- check if we need to wrap jsregexp to simulate the v0.1.0-style interface on
-- older versions.
local test_re, err = compile("^testregex$", "")
if not test_re then
	log.warn("Disabling jsregexp: Compiling test-regex gave error: %s", err)
	return false
end

if
	type(test_re) == "function"
	or (type(test_re) == "userdata" and getmetatable(test_re).__call ~= nil)
then
	log.debug("Compiled regex is function or has __call, wrapping it.")
	-- we have a jsregexp that supports the old call interface => add a
	-- wrapper.
	-- while v0.0.6 still supports the old interface, it's new interface
	-- contains a bug for regexes like (.*)/g, where it will match the second,
	-- zero-length match infinitely often.
	-- Thus, prefer wrapping the old interface if it is available.

	local function to_010_match(match, line)
		local res = match.groups
		res.index = match.begin_ind
		res[0] = line:sub(match.begin_ind, match.end_ind)
		return res
	end
	compile = function(...)
		local re = jsregexp.compile(...)
		return {
			exec = function(_, line)
				local matches_005 = re(line)
				if #matches_005 == 0 then
					return nil
				end

				return to_010_match(matches_005[1], line)
			end,
			match_all_list = function(_, line)
				local matches_005 = re(line)
				if #matches_005 == 0 then
					return matches_005
				end

				local matches_010 = {}
				for _, match_005 in ipairs(matches_005) do
					table.insert(matches_010, to_010_match(match_005, line))
				end
				return matches_010
			end,
		}
	end
else
	log.debug(
		"Compiled regex already has functional :exec and :match_all_list."
	)
end

return compile
