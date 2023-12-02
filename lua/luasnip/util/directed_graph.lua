local tbl_util = require("luasnip.util.table")
local autotable = require("luasnip.util.auto_table").autotable

local DirectedGraph = {}

-- set __index directly in DirectedGraph, otherwise each DirectedGraph-object would have its'
-- own metatable (one more table around), which would not be bad, but
-- unnecessary nonetheless.
DirectedGraph.__index = DirectedGraph

local Vertex = {}
Vertex.__index = Vertex

local function new_graph()
	return setmetatable({
		-- all vertices of this graph.
		vertices = {},
	}, DirectedGraph)
end
local function new_vertex()
	return setmetatable({
		-- vertices this vertex has an edge from/to.
		-- map[vert -> bool]
		incoming_edge_verts = {},
		outgoing_edge_verts = {},
	}, Vertex)
end

---Add new vertex to the DirectedGraph
---@return table: the generated vertex, to be used in `set_edge`, for example.
function DirectedGraph:add_vertex()
	local vert = new_vertex()
	table.insert(self.vertices, vert)
	return vert
end

---Remove vertex and its edges from DirectedGraph.
---@param v table: the vertex.
function DirectedGraph:clear_vertex(v)
	if not vim.tbl_contains(self.vertices, v) then
		-- vertex does not belong to this graph. Maybe throw error/make
		-- condition known?
		return
	end
	-- remove outgoing..
	for outgoing_edge_vert, _ in pairs(v.outgoing_edge_verts) do
		self:clear_edge(v, outgoing_edge_vert)
	end
	-- ..and incoming edges with v from the graph.
	for incoming_edge_vert, _ in pairs(v.incoming_edge_verts) do
		self:clear_edge(incoming_edge_vert, v)
	end
end

---Add edge from v1 to v2
---@param v1 table: vertex in the graph.
---@param v2 table: vertex in the graph.
function DirectedGraph:set_edge(v1, v2)
	if v1.outgoing_edge_verts[v2] then
		-- the edge already exists. Don't return an error, for now.
		return
	end
	-- link vertices.
	v1.outgoing_edge_verts[v2] = true
	v2.incoming_edge_verts[v1] = true
end

---Remove edge from v1 to v2
---@param v1 table: vertex in the graph.
---@param v2 table: vertex in the graph.
function DirectedGraph:clear_edge(v1, v2)
	assert(v1.outgoing_edge_verts[v2], "nonexistent edge cannot be removed.")
	-- unlink vertices.
	v1.outgoing_edge_verts[v2] = nil
	v2.incoming_edge_verts[v1] = nil
end

---Find and return verts with indegree 0.
---@param graph table: graph.
---@return table of vertices.
local function source_verts(graph)
	local indegree_0_verts = {}
	for _, vert in ipairs(graph.vertices) do
		if vim.tbl_count(vert.incoming_edge_verts) == 0 then
			table.insert(indegree_0_verts, vert)
		end
	end
	return indegree_0_verts
end

---Copy graph.
---@param graph table: graph.
---@return table,table: copied graph and table for mapping copied node to
---original node(original_vert[some_vert_from_copy] -> corresponding original
---vert).
local function graph_copy(graph)
	local copy = vim.deepcopy(graph)
	local original_vert = {}
	for i, copy_vert in ipairs(copy.vertices) do
		original_vert[copy_vert] = graph.vertices[i]
	end
	return copy, original_vert
end

---Generate a (it's not necessarily unique) topological sorting of this graphs
---vertices.
---https://en.wikipedia.org/wiki/Topological_sorting, this uses Kahn's Algorithm.
---@return table|nil: sorted vertices of this graph, nil if there is no
---topological sorting (eg. if the graph has a cycle).
function DirectedGraph:topological_sort()
	local sorting = {}

	-- copy self so edges can be removed without affecting the real graph.
	local graph, original_vert = graph_copy(self)

	-- find vertices without incoming edges.
	-- invariant: at the end of each step, sources contains all vertices
	-- without incoming edges.
	local sources = source_verts(graph)
	while #sources > 0 do
		-- pop v from sources.
		local v = sources[#sources]
		sources[#sources] = nil

		-- v has no incoming edges, it can be next in the sorting.
		-- important!! don't insert v, insert the corresponding vertex from the
		-- original graph. The copied vertices are not known outside this
		-- function (alternative: maybe return indices in graph.vertices?).
		table.insert(sorting, original_vert[v])

		-- find vertices which, if v is removed from graph, have no more incoming edges.
		-- Those are sources after v is removed.
		for outgoing_edge_vert, _ in pairs(v.outgoing_edge_verts) do
			-- there is one edge, it has to be from v.
			if vim.tbl_count(outgoing_edge_vert.incoming_edge_verts) == 1 then
				table.insert(sources, outgoing_edge_vert)
			end
		end

		-- finally: remove v from graph and sources.
		graph:clear_vertex(v)
	end

	if #sorting ~= #self.vertices then
		-- error: the sorting does not contain all vertices -> the graph has a cycle.
		return nil
	end
	return sorting
end

-- return all vertices reachable from this one.
function DirectedGraph:connected_component(vert, edge_direction)
	local outgoing_vertices_field = edge_direction == "Backward"
			and "incoming_edge_verts"
		or "outgoing_edge_verts"

	local visited = {}
	local to_visit = { [vert] = true }

	-- get any value in table.
	local next_vert, _ = next(to_visit, nil)
	while next_vert do
		to_visit[next_vert] = nil
		visited[next_vert] = true

		for neighbor, _ in pairs(next_vert[outgoing_vertices_field]) do
			if not visited[neighbor] then
				to_visit[neighbor] = true
			end
		end

		next_vert, _ = next(to_visit, nil)
	end

	return tbl_util.set_to_list(visited)
end

-- Very useful to have a graph where vertices are associated with some label.
-- This just proxies DirectedGraph and swaps labels and vertices in
-- parameters/return-values.
local LabeledDigraph = {}
LabeledDigraph.__index = LabeledDigraph

local function new_labeled_graph()
	return setmetatable({
		graph = new_graph(),
		label_to_vert = {},
		vert_to_label = {},
		-- map label -> origin-vert -> dest-vert
		label_to_verts = autotable(3, { warn = false }),
		-- map edge (origin,dest) to set of labels.
		verts_to_label = autotable(3, { warn = false }),
	}, LabeledDigraph)
end

function LabeledDigraph:set_vertex(label)
	if self.label_to_vert[label] then
		-- don't add same label again.
		return
	end

	local vert = self.graph:add_vertex()
	self.label_to_vert[label] = vert
	self.vert_to_label[vert] = label
end

function LabeledDigraph:set_edge(lv1, lv2, edge_label)
	-- ensure vertices exist.
	self:set_vertex(lv1)
	self:set_vertex(lv2)

	if self.verts_to_label[lv1][lv2][edge_label] then
		-- edge exists, do nothing.
		return
	end

	-- determine before setting the lv1-lv2-edge.
	local other_edge_exists = next(self.verts_to_label[lv1][lv2], nil) ~= nil

	-- store both associations;
	self.verts_to_label[lv1][lv2][edge_label] = true
	self.label_to_verts[edge_label][lv1][lv2] = true

	if other_edge_exists then
		-- there already exists an entry for this edge, no need to add it to
		-- the graph.
		return
	end
	self.graph:set_edge(self.label_to_vert[lv1], self.label_to_vert[lv2])
end

function LabeledDigraph:clear_edge(lv1, lv2, ledge)
	if not self.verts_to_label[lv1][lv2][ledge] then
		-- edge does not exist, do nothing.
		return
	end

	self.verts_to_label[lv1][lv2][ledge] = nil
	if next(self.verts_to_label[lv1][lv2]) == nil then
		-- removed last edge between v1, v2 -> remove edge in graph.
		self.graph:clear_edge(self.label_to_vert[lv1], self.label_to_vert[lv2])
	end
end
function LabeledDigraph:clear_edges(label)
	for lv1, lv2 in pairs(self.label_to_verts[label]) do
		self:clear_edge(lv1, lv2, label)
	end
	-- set to nil, not {}, so autotable can work its magic.
	self.label_to_verts[label] = nil
end

function LabeledDigraph:connected_component(lv, edge_direction)
	self:set_vertex(lv)

	return vim.tbl_map(function(v)
		return self.vert_to_label[v]
	end, self.graph:connected_component(self.label_to_vert[lv], edge_direction))
end

return {
	new = new_graph,
	new_labeled = new_labeled_graph,
}
