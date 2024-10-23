local M = {}

function M.ge(maj, min, patch)
	local version = vim.version()
	return
		(version.major > maj)
			or (version.major == maj and version.minor > min)
			or (
				version.major == maj
				and version.minor == min
				and version.patch >= patch
			)
end

return M
