{
  description = "NixOS WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = function: lib.genAttrs systems (system: function nixpkgs.legacyPackages.${system});

      np = import nixpkgs;

      mkPkgs = {system, buildPlatform ? null}@platformArgs:
       if buildPlatform == null then
          np {localSystem.system = system;}
        else np {
          crossSystem.system = system;
          localSystem.system = buildPlatform;
          config.warnUndeclaredOptions = true;
          # allow NixOS system config cross compilation
          config.allowUnsupportedSystem = true;
        };

      mkSystem = {system, buildPlatform ? null}@platformArgs: mkSystemF {
        inherit system;
        pkgs = mkPkgs platformArgs;
      };

      mkSystemF = {system, pkgs}: lib.nixosSystem {
          inherit system;
          modules = [
            {
              nixpkgs.pkgs = pkgs;
            }
            self.nixosModules.default
            ({ config, lib, pkgs, ... }: {
              # This config is only used until the first nixos-rebuild. For the config installed to /etc/nixos/configuration.nix, see modules/build-tarball.nix

              wsl.enable = true;

              programs.bash.loginShellInit = "nixos-wsl-welcome";

              # When the config is built from a flake, the NIX_PATH entry of nixpkgs is set to its flake version.
              # Per default the resulting systems aren't flake-enabled, so rebuilds would fail.
              # Note: This does not affect the module being imported into your own flake.
              nixpkgs.flake.source = lib.mkForce null;

              systemd.tmpfiles.rules =
                let
                  channels = pkgs.runCommand "default-channels" { } ''
                    mkdir -p $out
                    ln -s ${pkgs.path} $out/nixos
                    ln -s ${./.} $out/nixos-wsl
                  '';
                in
                [
                  "L /nix/var/nix/profiles/per-user/root/channels-1-link - - - - ${channels}"
                  "L /nix/var/nix/profiles/per-user/root/channels - - - - channels-1-link"
                ];
              system.stateVersion = config.system.nixos.release;
            })
          ];
        };
    in
    {
      nixosModules.wsl = {
        imports = [
          ./modules

          (_: {
            wsl.version.rev = lib.mkIf (self ? rev) self.rev;
          })
        ];
      };
      nixosModules.default = self.nixosModules.wsl;

      nixosConfigurations = (lib.genAttrs systems (system: mkSystem {inherit system;})) // {
        default = self.nixosConfigurations.x86_64-linux;

        modern = lib.warn "nixosConfigurations.modern has been renamed to nixosConfigurations.default" self.nixosConfigurations.default;

        legacy = throw "nixosConfigurations.legacy has been removed as syschdemd has been removed";
      };

      nixosConfigurationsForBuildSystem = let
        f = s1: {
          name = s1;
          value = lib.listToAttrs (map (s2: {
            name = s2;
            value = mkSystem {
              system = s1;
              buildPlatform = s2;
            };
          }) (lib.remove s1 systems));
        };
       in lib.listToAttrs (map f systems);

      tarballBuilders = {
        nativeSystems = builtins.mapAttrs (_name: madesys:
          madesys.config.system.build.tarballBuilderFun {inherit (madesys) pkgs lib;}
        ) self.nixosConfigurations;
        crossSystems = builtins.mapAttrs (to-sys-name: from-systems:
          builtins.mapAttrs (from-sys-name: madesys: let
              nativesys = self.nixosConfigurations.${from-sys-name};
            in
            madesys.config.system.build.tarballBuilderFun {inherit (nativesys) pkgs lib;}
          ) from-systems
        ) self.nixosConfigurationsForBuildSystem;
      };

      checks = forAllSystems (
        pkgs:
        let
          args = { inherit inputs; };
        in
        {
          dotnet-format = pkgs.callPackage ./checks/dotnet-format.nix args;
          nixpkgs-fmt = pkgs.callPackage ./checks/nixpkgs-fmt.nix args;
          nixpkgs-input = pkgs.callPackage ./checks/nixpkgs-input.nix args;
          rustfmt = pkgs.callPackage ./checks/rustfmt.nix args;
          side-effects = pkgs.callPackage ./checks/side-effects.nix args;
          username = pkgs.callPackage ./checks/username.nix args;
          test-native-utils = self.packages.${pkgs.stdenv.hostPlatform.system}.utils;
        }
      );

      packages = forAllSystems (pkgs: {
        utils = pkgs.callPackage ./utils { };
        staticUtils = pkgs.pkgsStatic.callPackage ./utils { };
        docs = pkgs.callPackage ./docs { };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          nativeBuildInputs = with pkgs; [
            cargo
            clippy
            mdbook
            nixpkgs-fmt
            powershell
            rustc
            rustfmt
            shfmt
          ];
        };
      });
    };
}
