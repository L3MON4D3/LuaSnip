NVIM_PATH=deps/nvim
nvim:
	git clone --depth 1 https://github.com/neovim/neovim ${NVIM_PATH} || (cd ${NVIM_PATH}; git fetch --depth 1; git checkout origin/master)

JSREGEXP_PATH=deps/jsregexp
jsregexp:
	git submodule init
	git submodule update
	# conditional: find lua nvim is linked against, and link against it too.
	make INCLUDE_DIR=-I$(shell pwd)/deps/lua51_include/ LDLIBS=$(if nvim -v | grep LuaJIT,"-lluajit-5.1","-llua5.1") -C ${JSREGEXP_PATH}

install_jsregexp: jsregexp
	# access via require("luasnip-jsregexp")
	# The hyphen must be used here, otherwise the luaopen_*-call will fail.
	# See the package.loaders-section [here](https://www.lua.org/manual/5.1/manual.html#pdf-require)
	cp $(shell pwd)/${JSREGEXP_PATH}/jsregexp.so $(shell pwd)/lua/luasnip-jsregexp.so

uninstall_jsregexp:
	rm $(shell pwd)/lua/luasnip-jsregexp.so

# Expects to be run from repo-location (eg. via `make -C path/to/luasnip`).
test: nvim jsregexp
	# unset both to prevent env leaking into the neovim-build.
	unset LUA_PATH LUA_CPATH
	# add helper-functions to lpath.
	# ";;" in CPATH appends default.
	LUASNIP_SOURCE=$(shell pwd) JSREGEXP_PATH=$(shell pwd)/${JSREGEXP_PATH} TEST_FILE=$(realpath tests) BUSTED_ARGS=--lpath=$(shell pwd)/tests/?.lua make -C ${NVIM_PATH} functionaltest
