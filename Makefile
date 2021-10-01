# clone plenary or update if it already exists.
PLENARY_PATH=deps/plenary.nvim
plenary:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim ${PLENARY_PATH} || git -C ${PLENARY_PATH} pull

# Expects to be run from repo-location (eg. via `make -C path/to/luasnip`).
test: plenary
	# Add plenary and luasnip to runtimepath, runtime! plenary.vim for
	# `PlenaryBustedDirectory`.
	nvim --headless --noplugin \
		-c "set runtimepath+=.,${PLENARY_PATH}" \
		-c "runtime! plugin/plenary.vim" \
		-c "lua require('luasnip.config').setup({})" \
		-c "PlenaryBustedDirectory tests"
