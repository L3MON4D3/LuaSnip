local helpers = require("test.functional.helpers")(after_each)

local works = function(snippets, opts) end

describe("snippet_collection.add/get", function()
	-- apparently clear() needs to run before anything else...
	helpers.clear()
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	it("get_id", function()
		local function foo()
			return helpers.exec_lua([[
				local s,t = require("luasnip").snippet, require("luasnip").text_node
				local collection = require("luasnip.session.snippet_collection")
				collection.clear_snippets()
				local s1,s2 = s("trig1", t("snippet1")), s("trig2", t("snippet2"))
				local opts = {type="snippets", default_priority=1000}
				collection.add_snippets({["txt"]={s1,s2}}, opts)
				return collection.get_id_snippet(s1.id) == s1
				]])
		end
		assert.has_no.errors(foo)
		assert.is_true(foo())
	end)

	it("get_snippets", function()
		local function foo()
			return helpers.exec_lua([[
				local s,t = require("luasnip").snippet, require("luasnip").text_node
				local collection = require("luasnip.session.snippet_collection")
				collection.clear_snippets()
				local s1,s2 = s("trig1", t("snippet1")), s("trig2", t("snippet2"))
				local opts = {type="snippets", default_priority=1000}
				collection.add_snippets({["txt"]={s1,s2}}, opts)
				local r = collection.get_snippets(nil, "snippets")
				assert(getmetatable(r) == nil)
				for _,t in pairs(r) do
					assert(getmetatable(t) == nil)
				end
				r = collection.get_snippets("txt", "snippets")
				assert(getmetatable(r) == nil)
				return #r == 2 and ((r[1] == s1 and r[2] == s2) or (r[1] == s2 and r[2] == s1))
				]])
		end
		assert.has_no.errors(foo)
		assert.is_true(foo())
	end)
end)

describe("add_snippets invalidation", function()
	-- apparently clear() needs to run before anything else...
	helpers.clear()
	helpers.exec("set rtp+=" .. os.getenv("LUASNIP_SOURCE"))

	it("", function()
		local function foo()
			return helpers.exec_lua([[
					local s,t = require("luasnip").snippet, require("luasnip").text_node
					local collection = require("luasnip.session.snippet_collection")
					collection.clear_snippets()
					local s1,s2 = s("trig1", t("snippet1")), s("trig2", t("snippet2"))
					local opts = {type="snippets", default_priority=1000, key="abc"}
					collection.add_snippets({["txt"]={s1,s2}}, opts)
					collection.clean_invalidated({ inv_limit = -1 })
					local r = collection.get_snippets("nonExistantFT", "snippets")
					]])
		end
		assert.has_no.errors(foo)
	end)
end)
