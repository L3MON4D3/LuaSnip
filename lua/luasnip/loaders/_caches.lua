local c = {
	lazy_load_paths = {},
	lazy_loaded_ft = {},
}
function c.clean()
	c.lazy_load_paths = {}
	c.lazy_loaded_ft = {}
end

return c
