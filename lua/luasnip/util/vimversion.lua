local M = {}

local version = vim.version()
function M.ge(maj, min, patch)
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
