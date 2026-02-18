{ lib, config, myLib, ... }:
{
  options.nixosHosts = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = {};
    description = "Mapping of hostname to NixOS configuration entrypoint path";
  };

  config = {
    nixosHosts = {
      saturn   = ../hosts/saturn/configuration.nix;
      mars     = ../hosts/mars/configuration.nix;
      luna     = ../hosts/luna/configuration.nix;
      eros     = ../hosts/eros/configuration.nix;
      ganymede = ../hosts/ganymede/configuration.nix;
    };

    flake.nixosConfigurations = lib.mapAttrs
      (_: path: myLib.mkSystem path)
      config.nixosHosts;
  };
}
