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
      rebar3 = pkgs.rebar3;
    in {
      devShell = pkgs.mkShell {
        buildInputs = [ elixir erl watchman rebar3 ];
        shellHook = ''
          export MIX_HOME=$PWD/.nix/mix
          export HEX_HOME=$PWD/.nix/hex
          export ERL_AFLAGS="-kernel shell_history enabled"
          mkdir -p $MIX_HOME $HEX_HOME
        '';
      };
    });
}
