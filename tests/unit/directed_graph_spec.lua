local helpers = require("test.functional.helpers")(after_each)
local exec_lua = helpers.exec_lua

describe("luasnip.util.directed_graph:", function()
	-- count and edges separately because
	-- 1. it's easier and
	-- 2. otherwise (pass only edges) we can't create vertices without edges.
	local function check_topsort(mess, v_count, edges, out_expected)
		it(mess, function()
			assert.are.same(
				out_expected,
				exec_lua(
					[[
					local v_count, edges = ...
					verts = {}

					local g = require("luasnip.util.directed_graph").new()
					for i = 1, v_count do
						verts[i] = g:add_vertex()
					end
					for _, edge in ipairs(edges) do
						-- ] ] to not end string.
						g:add_edge(verts[edge[1] ], verts[edge[2] ])
					end

					local sorting = g:topological_sort()

					local graph_verts_reverse =
						require("luasnip.util.util").reverse_lookup(g.vertices)
					-- sorting unsuccessful -> return nil.
					if not sorting then
						return "invalid"
					end
					-- return its index instead of the vertex.
					return vim.tbl_map(function(vert)
						return graph_verts_reverse[vert]
					end, sorting)
				]],
					v_count,
					edges
				)
			)
		end)
	end

	check_topsort(
		"simple check with unique sorting.",
		4,
		{ { 1, 2 }, { 2, 3 }, { 3, 4 } },
		{ 1, 2, 3, 4 }
	)
	check_topsort(
		"another simple unique check, with more complicated dependencies.",
		4,
		-- not going to add asciiart here, just draw the graph.
		{ { 3, 1 }, { 3, 2 }, { 4, 2 }, { 2, 1 }, { 3, 4 } },
		{ 3, 4, 2, 1 }
	)
	check_topsort(
		"more 'complicated' check (more edges).",
		5,
		-- draw it.
		{ { 5, 1 }, { 3, 1 }, { 5, 3 }, { 3, 4 }, { 3, 2 }, { 1, 2 }, { 2, 4 } },
		{ 5, 3, 1, 2, 4 }
	)
	check_topsort(
		"finds circles.",
		5,
		{ { 1, 5 }, { 5, 3 }, { 3, 2 }, { 2, 4 }, { 1, 2 }, { 2, 3 } },
		"invalid"
	)
	check_topsort(
		"finds circles again, also with lone points for confusion or something.",
		5,
		{ { 1, 3 }, { 3, 1 }, { 4, 1 }, { 4, 2 }, { 2, 1 } },
		"invalid"
	)
end)
