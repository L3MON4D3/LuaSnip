local id_to_source = {}

local M = {}

function M.from_debuginfo(debuginfo)
	assert(debuginfo.source, "debuginfo contains source")
	assert(
		debuginfo.source:match("^@"),
		"debuginfo-source is a file: " .. debuginfo.source
	)

	return {
		-- omit leading '@'.
		file = debuginfo.source:sub(2),
		line = debuginfo.currentline,
	}
end

function M.from_location(file, opts)
	assert(file, "source needs file")
	opts = opts or {}

	return { file = file, line = opts.line, line_end = opts.line_end }
end

function M.set(snippet, source)
	-- snippets only get their id after being added, make sure this is the
	-- case.
	assert(snippet.id, "snippet has an id")

	id_to_source[snippet.id] = source
end

function M.get(snippet)
	return id_to_source[snippet.id]
end

return M
