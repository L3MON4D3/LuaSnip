local Path = {}

local uv = vim.loop

local sep = (function()
	if jit then
		local os = jit.os:lower()
		if vim.tbl_contains({ "linux", "osx", "bsd" }, os) then
			return "/"
		else
			return "\\"
		end
	end
	return package.config:sub(1, 1)
end)()

local root_pattern = (function()
	return uv.os_uname().sysname:find("Windows") and "%w%:" or "%/"
end)()

function Path.join(...)
	return table.concat({ ... }, sep)
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

-- sometimes we don't want to resolve symlinks, but handle ~/ and ./
function Path.expand_keep_symlink(filepath)
	-- omit second return-value of :gsub
	local res = filepath:gsub("^[.][/\\]", MYCONFIG_ROOT .. sep)

	-- HOME may not exist in stripped-down environments.
	if vim.env.HOME then
		res = res:gsub("^~", vim.env.HOME)
	end

	return res
end
function Path.expand(filepath)
	return uv.fs_realpath(Path.expand_keep_symlink(filepath))
end

-- do our best at normalizing a non-existing path.
function Path.normalize_nonexisting(filepath, cwd)
	cwd = cwd or vim.fn.getcwd()

	local normalized = filepath
		-- replace multiple slashes by one.
		:gsub(sep .. sep .. "+", sep)
		-- remove trailing slash.
		:gsub(sep .. "$", "")
		-- remove ./ from path.
		:gsub("%." .. sep, "")

	-- if not yet absolute, prepend path to current directory.
	if not normalized:match("^" .. root_pattern .. "") then
		normalized = Path.join(cwd, normalized)
	end

	return normalized
end

function Path.expand_nonexisting(filepath, cwd)
	return Path.normalize_nonexisting(Path.expand_keep_symlink(filepath), cwd)
end

-- do our best at expanding a path that may or may not exist (ie. check if it
-- exists, if so do regular expand, and guess expanded path otherwise)
-- Not the clearest name :/
function Path.expand_maybe_nonexisting(filepath, cwd)
	local real_expanded = Path.expand(filepath)
	if not real_expanded then
		real_expanded = Path.expand_nonexisting(filepath, cwd)
	end
	return real_expanded
end

function Path.normalize_maybe_nonexisting(filepath, cwd)
	local real_normalized = Path.normalize(filepath)
	if not real_normalized then
		real_normalized = Path.normalize_nonexisting(filepath, cwd)
	end
	return real_normalized
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
			-- On networked filesystems, it can happen that we get
			-- a name, but no type. In this case, we must query the
			-- type manually via fs_stat(). See issue:
			-- https://github.com/luvit/luv/issues/660
			if name and not type then
				local stat = uv.fs_stat(path)
				type = stat and stat.type
			end
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
	local base = filepath
	if base:find(sep) then
		base = base:match(("%s([^%s]+)$"):format(sep, sep))
	end
	if ext then
		return base:match("(.*)%.(.+)")
	else
		return base
	end
end

function Path.extension(fname)
	return fname:match("%.([^%.]+)$")
end

function Path.components(path)
	return vim.split(path, sep, { plain = true, trimempty = true })
end

---Get parent of a path, without trailing separator
---if path is a directory or does not have a parent, returns nil
---Example:
---  On platforms that use "\\" backslash as path separator, e.g., Windows:
---    Path.parent("C:/project_root/file.txt") -- returns "C:/project_root"
---    Path.parent([[C:\project_root\file.txt]]) -- returns [[C:\project_root]]
---
---    -- the followings return `nil`s
---    Path.parent("C:/")
---    Path.parent([[C:\]])
---    Path.parent([[C:\project_root\]])
---
---    -- WARN: although it's unlikely that we will reach the driver's root
---    -- level, Path.parent("C:\file.txt") returns "C:", and please be
---    -- cautious when passing the parent path to some vim functions because
---    -- some vim functions on Windows treat "C:" as a file instead:
---    --   vim.fn.fnamemodify("C:", ":p") -- returns $CWD .. sep .. "C:"
---    -- To get the desired result, use vim.fn.fnamemodify("C:" .. sep, ":p")
---
---  On platforms that use "/" forward slash as path separator, e.g., linux:
---    Path.parent("/project_root/file.txt") returns "/project_root"
---    Path.parent("/file.txt") returns ""
---
---    -- the followings return `nil`s
---    Path.parent("/")
---    Path.parent("/project_root/")
---
---    -- backslash in a valid filename character in linux:
---    Path.parent([[/project_root/\valid\file\name.txt]]) returns "/project_root"
Path.parent = (function()
	---@alias PathSeparator "/" | "\\"
	---@param os_sep PathSeparator
	---@return fun(string): string | nil
	local function generate_parent(os_sep)
		if os_sep == "/" then
			---@param path string
			---@return string | nil
			return function(path)
				local last_component = path:match("[/]+[^/]+$")
				if not last_component then
					return nil
				end

				return path:sub(1, #path - #last_component)
			end
		else
			---@param path string
			---@return string | nil
			return function(path)
				local last_component = path:match("[/\\]+[^/\\]+$")
				if not last_component then
					return nil
				end

				return path:sub(1, #path - #last_component)
			end
		end
	end

	-- for test only
	if __LUASNIP_TEST_SEP_OVERRIDE then
		return generate_parent
	else
		return generate_parent(sep)
	end
end)()

-- returns nil if the file does not exist!
Path.normalize = uv.fs_realpath

return Path
