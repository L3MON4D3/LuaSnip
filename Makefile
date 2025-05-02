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

LUASNIP_DETECTED_OS?=$(shell uname;)

ifneq (,$(findstring Darwin, $(LUASNIP_DETECTED_OS)))
# flags for dynamic linking on macos, from luarocks
# (https://github.com/luarocks/luarocks/blob/9a3c5a879849f4f411a96cf1bdc0c4c7e26ade42/src/luarocks/core/cfg.lua#LL468C37-L468C80)
# remove -bundle, should be equivalent to the -shared hardcoded by jsregexp.
LUA_LDLIBS=-undefined dynamic_lookup -all_load
else ifneq (,$(or $(findstring MINGW,$(LUASNIP_DETECTED_OS)), $(findstring MSYS,$(LUASNIP_DETECTED_OS)), $(findstring CYGWIN,$(LUASNIP_DETECTED_OS))))
# If neovim is installed by scoop, only scoop/shims is exposed. We need to find original nvim/bin that contains lua51.dll
# If neovim is installed by winget or other methods, nvim/bin is already included in PATH.

# `scoop prefix neovim` outputs either
# 	1. C:\Users\MyUsername\scoop\apps\neovim\current
# 	2. Could not find app path for 'neovim'.
# On Git Bash, scoop returns 0 and writes error to stdout in case 2. This is tracked by
# @link: https://github.com/ScoopInstaller/Scoop/issues/6228
# The following code will also work if future scoop returns 1 for unknown `package`
#
# On Git Bash, `which nvim` returns a Unix style path: `/c/Program Files/Git/bin/nvim`
# Always convert to `C:/Program Files/Git/bin/nvim` for powershell and pwsh users
NEOVIM_BIN_PATH:=$(or \
	$(shell (scoop prefix neovim | grep -q '^[A-Z]:[/\\\\]') 2>/dev/null && \
	echo "$$(scoop prefix neovim)/bin" | sed 's/\\\\/\\//g';), \
	$(shell which nvim >/dev/null && dirname "$$(which nvim)" | sed 's/^\\/\\(.\\)\\//\\U\\1:\\//';) \
)
# Always double quote the absolute path as it may contain spaces
LUA_LDLIBS?=$(if $(strip $(NEOVIM_BIN_PATH)),-L"$(NEOVIM_BIN_PATH)" -llua51,)
endif

CC:=$(shell (which $(CC) || which gcc || which clang || (which zig >/dev/null && echo "$$(which zig) cc")) 2>/dev/null;)
ifeq (,$(CC))
$(error No compiler is provided in this environment. Please install a C compiler (gcc, clang, or zig).)
endif
PROJECT_ROOT:=$(CURDIR)
JSREGEXP_PATH=$(PROJECT_ROOT)/deps/jsregexp
JSREGEXP005_PATH=$(PROJECT_ROOT)/deps/jsregexp005
jsregexp:
	git submodule init
	git submodule update
	"$(MAKE)" "CC=$(CC)" "INCLUDE_DIR=-I$(PROJECT_ROOT)/deps/lua51_include/" 'LDLIBS=$(LUA_LDLIBS)' -C "$(JSREGEXP_PATH)"
	"$(MAKE)" "CC=$(CC)" "INCLUDE_DIR=-I$(PROJECT_ROOT)/deps/lua51_include/" 'LDLIBS=$(LUA_LDLIBS)' -C "$(JSREGEXP005_PATH)"

install_jsregexp: jsregexp
# remove old binary.
	rm -f "$(PROJECT_ROOT)/lua/luasnip-jsregexp.so"
# there is some additional trickery to make this work with jsregexp-0.0.6 in
# util/jsregexp.lua.
	cp "$(JSREGEXP_PATH)/jsregexp.lua" "$(PROJECT_ROOT)/lua/luasnip-jsregexp.lua"
# just move out of jsregexp-directory, so it is not accidentially deleted.
	cp "$(JSREGEXP_PATH)/jsregexp.so" "$(PROJECT_ROOT)/deps/luasnip-jsregexp.so"

uninstall_jsregexp:
# also remove binaries of older version.
	rm -f "$(PROJECT_ROOT)/lua/luasnip-jsregexp.so"
	rm -f "$(PROJECT_ROOT)/deps/luasnip-jsregexp.so"
	rm -f "$(PROJECT_ROOT)/lua/luasnip-jsregexp.lua"

TEST_07?=true
TEST_09?=true
TEST_MASTER?=true
PREVENT_LUA_PATH_LEAK?=true
# Expects to be run from repo-location (eg. via `make -C path/to/luasnip`).
test: nvim install_jsregexp
# unset PATH and CPATH to prevent system-env leaking into the neovim-build,
# add our helper-functions to lpath.
# exit as soon as an error occurs.
# For some Reason, on 0.9.0, `make functionaltest` has to be preceded by a regular make for doc to build.
	if ${PREVENT_LUA_PATH_LEAK}; then unset LUA_PATH LUA_CPATH; fi; \
	export LUASNIP_SOURCE=$(PROJECT_ROOT); \
	export JSREGEXP_ABS_PATH=$(JSREGEXP_PATH); \
	export JSREGEXP005_ABS_PATH=$(JSREGEXP005_PATH); \
	export TEST_FILE=$(realpath ${TEST_FILE}); \
	export BUSTED_ARGS=--lpath=$(PROJECT_ROOT)/tests/?.lua; \
	set -e; \
	if ${TEST_07}; then "$(MAKE)" -C ${NVIM_0.7_PATH} functionaltest DEPS_CMAKE_FLAGS=-DUSE_BUNDLED_GPERF=OFF -j; fi; \
	if ${TEST_09}; then "$(MAKE)" -C ${NVIM_0.9_PATH} -j; "$(MAKE)" -C ${NVIM_0.9_PATH} functionaltest -j; fi; \
	if ${TEST_MASTER}; then "$(MAKE)" -C ${NVIM_MASTER_PATH} functionaltest -j; fi;

test_nix: nvim install_jsregexp
	set -e; \
	if ${TEST_07}; then nix develop .#nvim_07 -c make test; fi; \
	if ${TEST_09}; then nix develop .#nvim_09 -c make test; fi; \
	if ${TEST_MASTER}; then nix develop .#nvim_master -c make test; fi;
