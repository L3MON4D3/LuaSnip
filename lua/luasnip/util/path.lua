local Path = {}

local uv = vim.loop

-- In windows, unix style paths are also valid
function Path.unixfy(path)
	if path:match("^[A-Z]:") then
		return path:gsub("\\", "/")
	end
	return path
end

function Path.join(...)
	return Path.unixfy(table.concat({ ... }, "/"))
end

function Path.exists(filepath)
	return uv.fs_stat(filepath) and true or false
end

function Path.async_read_file(path, callback)
	uv.fs_open(path, "r", tonumber("0666", 8), function(err, fd)
		assert(not err, err)
		uv.fs_fstat(fd, function(err, stat)
			assert(not err, err)
			uv.fs_read(fd, stat.size, 0, function(err, buffer)
				assert(not err, err)
				uv.fs_close(fd, function(err)
					assert(not err, err)
					callback(buffer)
				end)
			end)
		end)
	end)
end

---@param path string
---@return string buffer @content of file
function Path.read_file(path)
	-- permissions: rrr
	local fd = assert(uv.fs_open(path, "r", tonumber("0444", 8)))
	local stat = assert(uv.fs_fstat(fd))
	-- read from offset 0.
	local buf = assert(uv.fs_read(fd, stat.size, 0))
	uv.fs_close(fd)

	return buf
end

local MYCONFIG_ROOT

if vim.env.MYVIMRC then
	MYCONFIG_ROOT = vim.fn.fnamemodify(vim.env.MYVIMRC, ":p:h")
else
	MYCONFIG_ROOT = vim.fn.getcwd()
end

function Path.expand(filepath)
	local expanded = Path.unixfy(
		filepath:gsub("^~", vim.env.HOME):gsub("^[.]", MYCONFIG_ROOT)
	)
	return uv.fs_realpath(expanded)
end

---Return files and directories in path as a list
---@param root string
---@return string[] files, string[] directories
function Path.scandir(root)
	local files, dirs = {}, {}
	local fs = uv.fs_scandir(root)
	if fs then
		local name, type = "", ""
		while name do
			name, type = uv.fs_scandir_next(fs)
			local path = Path.join(root, name)
			if type == "file" then
				table.insert(files, path)
			elseif type == "directory" then
				table.insert(dirs, path)
			elseif type == "link" then
				local followed_path = uv.fs_realpath(path)
				if followed_path then
					local stat = uv.fs_stat(followed_path)
					if stat.type == "file" then
						table.insert(files, path)
					elseif stat.type == "directory" then
						table.insert(dirs, path)
					end
				end
			end
		end
	end
	return files, dirs
end

---Get basename
---@param filepath string
---@param ext boolean if true, separate the file extension
---@return string, string?
---Example:
---         Path.basename("~/.config/nvim/init.lua") -> init.lua
---         Path.basename("~/.config/nvim/init.lua", true) -> init, lua
function Path.basename(filepath, ext)
	local base = vim.fn.fnamemodify(filepath, ":t")
	if ext then
		return base:match("(.*)%.(.+)")
	else
		return base
	end
end

Path.normalize = uv.fs_realpath

return Path
