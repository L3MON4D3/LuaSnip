NVIM_PATH=deps/nvim
nvim:
	git clone --depth 1 https://github.com/neovim/neovim ${NVIM_PATH} || (cd ${NVIM_PATH}; git fetch --depth 1; git checkout origin/master)

JSREGEXP_PATH=deps/jsregexp
jsregexp:
	# rebuild on new pull, accept otherwise.
	git clone --depth 1 https://github.com/kmarius/jsregexp ${JSREGEXP_PATH} || (cd ${JSREGEXP_PATH}; git fetch --depth 1; git checkout origin/master)
	make -C ${JSREGEXP_PATH}

# Expects to be run from repo-location (eg. via `make -C path/to/luasnip`).
test: nvim jsregexp
	# unset both to prevent env leaking into the neovim-build.
	unset LUA_PATH LUA_CPATH
	# add helper-functions to lpath.
	# ";;" in CPATH appends default.
	LUASNIP_SOURCE=$(shell pwd) LUA_CPATH="$(shell pwd)/${JSREGEXP_PATH}/?.so;;" TEST_FILE=$(realpath tests) BUSTED_ARGS=--lpath=$(shell pwd)/tests/?.lua make -C ${NVIM_PATH} functionaltest
