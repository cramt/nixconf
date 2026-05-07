{ lib, config, myLib, inputs, ... }:
{
  options.nixosHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        config = lib.mkOption {
          type = lib.types.path;
          description = "Path to the host's configuration.nix";
        };
        nixpkgs = lib.mkOption {
          type = lib.types.unspecified;
          default = inputs.nixpkgs;
          description = "Which nixpkgs flake to build the system from. Override per-host to match a vendor cache (e.g. nixos-raspberrypi).";
        };
      };
    });
    default = {};
    description = "Mapping of hostname to NixOS configuration entrypoint";
  };

  config = {
    nixosHosts = {
      saturn.config   = ../../hosts/saturn/configuration.nix;
      mars.config     = ../../hosts/mars/configuration.nix;
      luna.config     = ../../hosts/luna/configuration.nix;
      eros = {
        config  = ../../hosts/eros/configuration.nix;
        nixpkgs = inputs.nixpkgs-rpi;
      };
      ganymede.config = ../../hosts/ganymede/configuration.nix;
    };

    flake.nixosConfigurations = lib.mapAttrs
      (_: host: myLib.mkSystem host)
      config.nixosHosts;
  };
}
