NVIM_PATH=deps/nvim
nvim:
	git clone --depth 1 https://github.com/neovim/neovim ${NVIM_PATH} || (cd ${NVIM_PATH}; git fetch --depth 1; git checkout origin/master)

OS:=$(shell uname)
LUAJIT:=$(shell nvim -v | grep -o LuaJIT)
ifeq ($(LUAJIT),LuaJIT)
	ifeq ($(OS),Darwin)
		LUA_LDLIBS=-lluajit-5.1.2 -L/opt/homebrew/opt/luajit/lib/
	else
		LUA_LDLIBS=-lluajit-5.1
	endif
else
	LUA_LDLIBS=-llua5.1
endif
JSREGEXP_PATH=deps/jsregexp
jsregexp:
	git submodule init
	git submodule update
	make INCLUDE_DIR=-I$(shell pwd)/deps/lua51_include/ LDLIBS="${LUA_LDLIBS}" -C ${JSREGEXP_PATH}

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
	# add helper-functions to lpath.
	# ";;" in CPATH appends default.
	unset LUA_PATH LUA_CPATH; LUASNIP_SOURCE=$(shell pwd) JSREGEXP_PATH=$(shell pwd)/${JSREGEXP_PATH} TEST_FILE=$(realpath tests) BUSTED_ARGS=--lpath=$(shell pwd)/tests/?.lua make -C ${NVIM_PATH} functionaltest
