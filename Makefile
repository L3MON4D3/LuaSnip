NVIM_PATH=deps/nvim
nvim:
	git clone --depth 1 https://github.com/neovim/neovim ${NVIM_PATH} || (cd ${NVIM_PATH}; git fetch --depth 1; git checkout origin/master)

# Expects to be run from repo-location (eg. via `make -C path/to/luasnip`).
test: nvim
	# unset both to prevent env leaking into the neovim-build.
	# add helper-functions to lpath.
	unset LUA_PATH LUA_CPATH ; LUASNIP_SOURCE=$(shell pwd) TEST_FILE=$(realpath tests) BUSTED_ARGS=--lpath=$(shell pwd)/tests/?.lua make -C ${NVIM_PATH} functionaltest
