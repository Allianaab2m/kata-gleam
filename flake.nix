{
  description = "A basic flake to with Gleam language";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    devenv.url = "github:cachix/devenv";
    gleam-overlay.url = "github:Comamoca/gleam-overlay";
    deno-overlay.url = "github:haruki7049/deno-overlay";
  };

  outputs =
    inputs@{
      self,
      systems,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.git-hooks-nix.flakeModule
        inputs.devenv.flakeModule
      ];
      systems = import inputs.systems;

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        let
          stdenv = pkgs.stdenv;

          erlangPackages = with pkgs.beamMinimal28Packages; [
            erlang
            rebar3
          ];

          # javascriptPackages =
          #   let
          #     # Get the latest version of Deno from deno-overlay.
          #     denoVersions = builtins.attrNames pkgs.deno;
          #     sorted = pkgs.lib.sort (a: b: pkgs.lib.versionOlder a b) denoVersions;
          #     latestVersion = pkgs.lib.last sorted;
          #   in
          #   with pkgs;
          #   [
          #     nodejs-slim
          #     pkgs.deno.${latestVersion}
          #     bun
          #   ];

          gleamPackages = with pkgs; [
            gleam.bin.latest
          ];
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              inputs.gleam-overlay.overlays.default
              inputs.deno-overlay.overlays.deno-overlay
            ];
            config = { };
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              gleam = {
                enable = true;
                package = pkgs.gleam.bin.latest;
              };
            };

            settings.formatter = { };
          };

          pre-commit = {
            check.enable = true;
            settings = {
              hooks = {
                treefmt.enable = true;
              };
            };
          };

          devShells.default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                nixd
              ]
              ++ erlangPackages
              # ++ javascriptPackages
              ++ gleamPackages;
          };
        };
    };
}
