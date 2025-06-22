{
  description = "A nix flake for developing LuaSnip.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  # has tree-sitter 0.20.8, which is required for neovim 0.9.0.
  inputs.nixpkgs-treesitter.url = "github:nixos/nixpkgs/7a339d87931bba829f68e94621536cad9132971a";

  inputs.nvim_07.url = "github:neovim/neovim/v0.7.0?dir=contrib";

  inputs.nvim_09.url = "github:neovim/neovim/v0.9.0?dir=contrib";

  # this only has to be updated sporadically, basically whenever the source in
  # worktree_master no longer builds.
  inputs.nvim_master.url = "github:nix-community/neovim-nightly-overlay";
  inputs.luals-mdgen.url = "github:L3MON4D3/luals-mdgen";
  inputs.emmylua-analyzer-rust.url = "github:EmmyLuaLs/emmylua-analyzer-rust";
  inputs.panvimdoc.url = "github:L3MON4D3/panvimdoc";

  outputs = {
    self,
    nixpkgs,
    nixpkgs-treesitter,
    nvim_07,
    nvim_09,
    nvim_master,
    luals-mdgen,
    emmylua-analyzer-rust,
    panvimdoc
  }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs-treesitter.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
        pkgs-treesitter = import nixpkgs-treesitter { inherit system; };
        pkgs-nvim_09 = import nvim_09.inputs.nixpkgs { inherit system; };
        pkgs-nvim_07 = import nvim_07.inputs.nixpkgs { inherit system; };
        pkg-luals-mdgen = luals-mdgen.outputs.packages.${system}.default;
        pkg-emmylua-doc = emmylua-analyzer-rust.outputs.packages.${system}.emmylua_doc_cli;
        pkg-panvimdoc = panvimdoc.outputs.packages.${system}.default;
      });
    in
    {
      devShells = forEachSupportedSystem ({
        pkgs,
        pkgs-treesitter,
        pkgs-nvim_09,
        pkgs-nvim_07,
        pkg-luals-mdgen,
        pkg-emmylua-doc,
        pkg-panvimdoc
      }: let
        default_09_devshell = nvim_09.outputs.devShells.${pkgs.system}.default;
        true_bin = "${pkgs.coreutils}/bin/true";
        false_bin = "${pkgs.coreutils}/bin/false";
      in {
        default = pkgs.mkShell {
          # use any nixpkgs here.
          packages = [
            (pkgs.aspellWithDicts (dicts: with dicts; [en]))
            pkgs.gnumake

            pkgs.git
            pkgs.nix
            pkgs.which
            pkgs.gnugrep
            pkgs.gcc
            pkg-luals-mdgen
            pkg-emmylua-doc
            pkg-panvimdoc
            pkgs.neovim
          ];
        };
        # clang stdenv does not build, and it's used by de.
        test_nvim_07 = (nvim_07.outputs.devShell.${pkgs.system}.override { stdenv = pkgs-nvim_07.gccStdenv; }).overrideAttrs(attrs: {
          TEST_07=true_bin;
          TEST_09=false_bin;
          TEST_MASTER=false_bin;

          # when using bundled dependencies, there are issues with luarocks :/
          # don't need to build treesitter-parsers, so we can just set this.
          USE_BUNDLED="OFF";

          LUA_PATH="";
          LUA_CPATH="";
          PREVENT_LUA_PATH_LEAK=false_bin;
          # ASAN does not work with gcc stdenv.
          cmakeFlags =  builtins.filter (x: x != "-DCLANG_ASAN_UBSAN=ON") attrs.cmakeFlags;

          # adjust some paths.
          # We're not running the devshell from the directory it expects.
          shellHook = ''
            cd ./deps/nvim_multiversion/worktree_0.7
            cmakeConfigurePhase
            cd ../../../../
          '';
        });

        # override default tree-sitter, it has the wrong version (0.20.7 vs required 0.20.8).
        test_nvim_09 = default_09_devshell.overrideAttrs(attrs: {
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

        test_nvim_master = nvim_master.outputs.devShells.${pkgs.system}.default.overrideAttrs(attrs: {
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
