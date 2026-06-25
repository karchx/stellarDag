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

      registry = "192.168.0.9:32000";
      heroicons-src = pkgs.fetchFromGitHub {
        owner = "tailwindlabs";
        repo = "heroicons";
        rev = "v2.2.0";
        hash = "sha256-A8JTVl0Yig++G2B8dyoq5gMpVRnU/wL4I74WK8sB6aU=";
        sparseCheckout = [
            "optimized"
        ];
      };
    in {
        packages = rec {
            stellar_core_deps = erlangPackages.fetchRebar3Deps {
                name = "stellar_core-deps";
                src = ./stellar_core;
                version = "0.1.0";
                sha256 = "sha256-l2+0H8Y9RtKqO4cmwbTjs8/yDn+rPB8WkYqm35fTDp8=";
            };
            stellar_core = erlangPackages.rebar3Relx {
                pname = "stellar_core";
                version = "0.1.0";
                src = ./stellar_core;
                releaseType = "release";

                checkouts = stellar_core_deps;
            };

            stellarweb_deps = erlangPackages.fetchMixDeps {
                pname = "mix-deps-stellarweb";
                version = "0.1.0";
                src = ./stellarweb;
                nativeBuildInputs = [ pkgs.git ];
                hash = "sha256-RCTpNDxts5qmWeF/yrqk5QIyCjrdoGamamRePXWoC8g=";
            };
            stellarweb = erlangPackages.mixRelease {
                pname = "stellarweb";
                version = "0.1.0";
                src = ./stellarweb;
                nativeBuildInputs = [ 
                    pkgs.nodejs
                    pkgs.esbuild
                    pkgs.tailwindcss_4
                ];
                mixFodDeps = stellarweb_deps;
                preBuild = ''
                    export MIX_ENV=prod
                    export ESBUILD_PATH=${pkgs.esbuild}/bin/esbuild
                    export TAILWIND_PATH=${pkgs.tailwindcss_4}/bin/tailwindcss

                    mkdir -p deps/heroicons
                    cp -r ${heroicons-src}/optimized deps/heroicons/optimized

                    mix tailwind oraculo --minify --no-deps-check
                    mix esbuild oraculo --minify --no-deps-check
                    mix phx.digest --no-deps-check
                '';
            };

            stellar_core-image = pkgs.dockerTools.buildLayeredImage {
                name = "stellar_core";
                tag = "latest";
                contents = [
                    pkgs.coreutils
                    pkgs.bash
                    pkgs.gawk
                    pkgs.gnugrep
                    pkgs.gnused
                    stellar_core
                ];
                config = {
                    Cmd = [ "${stellar_core}/bin/stellar_core" "foreground" ];
                    ExposedPorts = { "4369/tcp" = {}; };
                    Env = [ 
                        "LANG=C.UTF-8" 
                        "RELX_REPLACE_OS_VARS=true"
                    ];
                };
            };

            stellarweb-image = pkgs.dockerTools.buildLayeredImage {
                name = "stellarweb";
                tag = "latest";
                contents = [
                    pkgs.coreutils
                    pkgs.bash
                    stellarweb
                ];
                config = {
                    Cmd = [ "${stellarweb}/bin/stellarweb" "start" ];
                    ExposedPorts = { "4000/tcp" = {}; };
                    Env = [
                        "MIX_ENV=prod"
                        "PHX_SERVER=true"
                        "LANG=C.UTF-8"
                    ];
                };
            };

            deploy-script = pkgs.symlinkJoin {
                name = "deploy-stellar-scripts";
                paths = [
                    (pkgs.writeShellScriptBin "deploy-stellar-core" ''
                        set -e
                        
                        echo "🚀 Building OCI image with Nix..."
                        TAR_PATH=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths .#stellar_core-image)
                        
                        echo "📦 Loading OCI image into local registry..."
                        ${pkgs.skopeo}/bin/skopeo --insecure-policy copy --dest-tls-verify=false docker-archive:$TAR_PATH docker://${registry}/stellar/core:latest
                         
                        echo "✅ Deployment successful! ${registry}/stellar/core:latest"
                    '')
                    (pkgs.writeShellScriptBin "deploy-stellar-web" ''
                        set -e
                        
                        echo "🚀 Building OCI image with Nix..."
                        TAR_PATH=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths .#stellarweb-image)
                        
                        echo "📦 Loading OCI image into local registry..."
                        ${pkgs.skopeo}/bin/skopeo --insecure-policy copy --dest-tls-verify=false docker-archive:$TAR_PATH docker://${registry}/stellar/web:latest
                         
                        echo "✅ Deployment successful! ${registry}/stellar/web:latest"
                    '')
                ];
            }; 
        };

        apps = {
            deployStellarCore = {
                type = "app";
                program = "${self.packages.${system}.deploy-script}/bin/deploy-stellar-core";
            };

            deployStellarWeb = {
                type = "app";
                program = "${self.packages.${system}.deploy-script}/bin/deploy-stellar-web";
            };
        };

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
