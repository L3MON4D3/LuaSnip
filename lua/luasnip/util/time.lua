-- http://lua-users.org/wiki/TimeZone
local function get_timezone_offset(ts)
	local utcdate = os.date("!*t", ts)
	local localdate = os.date("*t", ts)
	localdate.isdst = false -- this is the trick
	local diff = os.difftime(os.time(localdate), os.time(utcdate))
	local h, m = math.modf(diff / 3600)
	return string.format("%+.4d", 100 * h + 60 * m)
end

return {
	get_timezone_offset = get_timezone_offset,
}
