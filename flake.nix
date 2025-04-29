{
  description = "A nix flake for developing LuaSnip.";

  # has tree-sitter 0.20.8, which is required for neovim 0.9.0.
  inputs.nixpkgs-treesitter.url = "github:nixos/nixpkgs/7a339d87931bba829f68e94621536cad9132971a";

  inputs.nvim_07.url = "github:neovim/neovim/v0.7.0?dir=contrib";

  inputs.nvim_09.url = "github:neovim/neovim/v0.9.0?dir=contrib";

  # this only has to be updated sporadically, basically whenever the source in
  # worktree_master no longer builds.
  inputs.nvim_master.url = "github:nix-community/neovim-nightly-overlay";

  outputs = { self, nixpkgs-treesitter, nvim_07, nvim_09, nvim_master }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs-treesitter.lib.genAttrs supportedSystems (system: f {
        pkgs-treesitter = import nixpkgs-treesitter { inherit system; };
        pkgs-nvim_09 = import nvim_09.inputs.nixpkgs { inherit system; };
      });
    in
    {
      devShells = forEachSupportedSystem ({ pkgs-treesitter, pkgs-nvim_09 }: let
        default_09_devshell = nvim_09.outputs.devShells.${pkgs-treesitter.system}.default;
        true_bin = "${pkgs-treesitter.coreutils}/bin/true";
        false_bin = "${pkgs-treesitter.coreutils}/bin/false";
      in {
        nvim_07 = nvim_07.outputs.devShell.${pkgs-treesitter.system}.overrideAttrs(attrs: {
          TEST_07=true_bin;
          TEST_09=false_bin;
          TEST_MASTER=false_bin;

          # when using bundled dependencies, there are issues with luarocks :/
          # don't need to build treesitter-parsers, so we can just set this.
          USE_BUNDLED="OFF";

          LUA_PATH="";
          LUA_CPATH="";
          PREVENT_LUA_PATH_LEAK=false_bin;

          # adjust some paths.
          # We're not running the devshell from the directory it expects.
          shellHook = builtins.replaceStrings
            [" outputs" " runtime" " build"]
            [" ./deps/nvim_multiversion/worktree_0.7/outputs" " ./deps/nvim_multiversion/worktree_0.7/runtime" " ./deps/nvim_multiversion/worktree_0.7/build"]
            attrs.shellHook;
        });

        # override default tree-sitter, it has the wrong version (0.20.7 vs required 0.20.8).
        nvim_09 = default_09_devshell.overrideAttrs(attrs: {
          TEST_07=false_bin;
          TEST_09=true_bin;
          TEST_MASTER=false_bin;

          # when using bundled dependencies, there are issues with luarocks :/
          # With USE_BUNDLED=OFF, DEPS_CMAKE_FLAGS is not even evaluated!
          # so, set it off only in there :)
          # only build parsers!
          DEPS_CMAKE_FLAGS="-D USE_BUNDLED=OFF -D USE_BUNDLED_TS_PARSERS=ON";

          # unset lua-path here, to make sure the global env does not leak, and
          # prevent unset later, s.t. the lua env imported by this flake
          # exists.
          LUA_PATH="";
          LUA_CPATH="";
          PREVENT_LUA_PATH_LEAK=false_bin;

          buildInputs = [
            pkgs-treesitter.pkgs.tree-sitter
          ] ++ attrs.buildInputs;

          # clear shellHook, it doesn't do anything we really need.
          shellHook = "";
        });

        nvim_master = nvim_master.outputs.devShells.${pkgs-treesitter.system}.default.overrideAttrs(attrs: {
          TEST_07=false_bin;
          TEST_09=false_bin;
          TEST_MASTER=true_bin;

          # same reasoning as in nvim_09
          DEPS_CMAKE_FLAGS="-D USE_BUNDLED=OFF -D USE_BUNDLED_TS_PARSERS=ON";

          # unset lua-path here, to make sure the global env does not leak, and
          # prevent unset later, s.t. the lua env imported by this flake
          # exists.
          LUA_PATH="";
          LUA_CPATH="";
          PREVENT_LUA_PATH_LEAK=false_bin;

          # clear shellHook, it doesn't do anything we really need.
          shellHook = "";
        });
      });
    };
}
