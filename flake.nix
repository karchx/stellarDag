{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      erl = pkgs.beam.interpreters.erlang_27;
      erlangPackages = pkgs.beam.packagesWith erl;
      elixir = erlangPackages.elixir;
      watchman = pkgs.watchman;
    in {
      devShell = pkgs.mkShell {
        buildInputs = [ elixir erl watchman ];
        shellHook = ''
          export MIX_HOME=$PWD/.nix/mix
          export HEX_HOME=$PWD/.nix/hex
          mkdir -p $MIX_HOME $HEX_HOME
        '';
      };
    });
}
