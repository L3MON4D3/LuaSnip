TEST_FILE?=$(realpath tests)

NVIM_PATH=deps/nvim_multiversion
# relative to ${NVIM_PATH} and relative to this makefile.
NVIM_MASTER_PATH_REL=worktree_master
NVIM_0.7_PATH_REL=worktree_0.7
NVIM_0.9_PATH_REL=worktree_0.9
NVIM_MASTER_PATH=${NVIM_PATH}/${NVIM_MASTER_PATH_REL}
NVIM_0.7_PATH=${NVIM_PATH}/${NVIM_0.7_PATH_REL}
NVIM_0.9_PATH=${NVIM_PATH}/${NVIM_0.9_PATH_REL}

# directory as target.
${NVIM_PATH}:
	# fetch current master and 0.7.0 (the minimum version we support) and 0.9.0
	# (the minimum version for treesitter-postfix to work).
	git clone --bare --depth 1 https://github.com/neovim/neovim ${NVIM_PATH}
	git -C ${NVIM_PATH} fetch --depth 1 origin tag v0.7.0
	git -C ${NVIM_PATH} fetch --depth 1 origin tag v0.9.0
	# create one worktree for master, and one for 0.7.
	# The rationale behind this is that switching from 0.7 to master (and
	# vice-versa) requires a `make distclean`, and full clean build, which takes
	# a lot of time.
	# The most straightforward solution seems to be too keep two worktrees, one
	# for master, one for 0.7, and one for 0.9 which are used for the
	# respective builds/tests.
	git -C ${NVIM_PATH} worktree add ${NVIM_MASTER_PATH_REL} master
	git -C ${NVIM_PATH} worktree add ${NVIM_0.7_PATH_REL} v0.7.0
	git -C ${NVIM_PATH} worktree add ${NVIM_0.9_PATH_REL} v0.9.0

# |: don't update `nvim` if `${NVIM_PATH}` is changed.
nvim: | ${NVIM_PATH}
	# only update master
	git -C ${NVIM_MASTER_PATH} fetch origin master --depth 1
	git -C ${NVIM_MASTER_PATH} checkout FETCH_HEAD

LUASNIP_DETECTED_OS?=$(shell uname)
ifeq ($(LUASNIP_DETECTED_OS),Darwin)
	# flags for dynamic linking on macos, from luarocks
	# (https://github.com/luarocks/luarocks/blob/9a3c5a879849f4f411a96cf1bdc0c4c7e26ade42/src/luarocks/core/cfg.lua#LL468C37-L468C80)
	# remove -bundle, should be equivalent to the -shared hardcoded by jsregexp.
	LUA_LDLIBS=-undefined dynamic_lookup -all_load
endif

JSREGEXP_PATH=deps/jsregexp
JSREGEXP005_PATH=deps/jsregexp005
jsregexp:
	git submodule init
	git submodule update
	make "INCLUDE_DIR=-I$(shell pwd)/deps/lua51_include/" LDLIBS="${LUA_LDLIBS}" -C ${JSREGEXP_PATH}
	make "INCLUDE_DIR=-I$(shell pwd)/deps/lua51_include/" LDLIBS="${LUA_LDLIBS}" -C ${JSREGEXP005_PATH}

install_jsregexp: jsregexp
	# remove old binary.
	rm "$(shell pwd)/lua/luasnip-jsregexp.so" || true
	# there is some additional trickery to make this work with jsregexp-0.0.6 in
	# util/jsregexp.lua.
	cp "$(shell pwd)/${JSREGEXP_PATH}/jsregexp.lua" "$(shell pwd)/lua/luasnip-jsregexp.lua"
	# just move out of jsregexp-directory, so it is not accidentially deleted.
	cp "$(shell pwd)/${JSREGEXP_PATH}/jsregexp.so" "$(shell pwd)/deps/luasnip-jsregexp.so"

uninstall_jsregexp:
	# also remove binaries of older version.
	rm "$(shell pwd)/lua/luasnip-jsregexp.so"
	rm "$(shell pwd)/lua/deps/luasnip-jsregexp.so"
	rm "$(shell pwd)/lua/luasnip-jsregexp.lua"

TEST_07?=true
TEST_09?=true
TEST_MASTER?=true
# Expects to be run from repo-location (eg. via `make -C path/to/luasnip`).
test: nvim install_jsregexp
	# unset PATH and CPATH to prevent system-env leaking into the neovim-build,
	# add our helper-functions to lpath.
	# exit as soon as an error occurs.
	unset LUA_PATH LUA_CPATH; \
	export LUASNIP_SOURCE=$(shell pwd); \
	export JSREGEXP_ABS_PATH=$(shell pwd)/${JSREGEXP_PATH}; \
	export JSREGEXP005_ABS_PATH=$(shell pwd)/${JSREGEXP005_PATH}; \
	export TEST_FILE=$(realpath ${TEST_FILE}); \
	export BUSTED_ARGS=--lpath=$(shell pwd)/tests/?.lua; \
	set -e; \
	if ${TEST_07}; then make -C ${NVIM_0.7_PATH} functionaltest DEPS_CMAKE_FLAGS=-DUSE_BUNDLED_GPERF=OFF; fi; \
	if ${TEST_09}; then make -C ${NVIM_0.9_PATH} functionaltest; fi; \
	if ${TEST_MASTER}; then make -C ${NVIM_MASTER_PATH} functionaltest; fi;
