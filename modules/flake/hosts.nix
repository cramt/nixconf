{ lib, config, myLib, inputs, ... }:
let
  hostsDir = ../../hosts;

  # hosts/ holds exactly the NixOS hosts — one directory each — so the fleet is
  # discovered rather than listed. Adding a machine is "make the folder".
  hostNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir hostsDir)
  );

  knobsFor = name: hostsDir + "/${name}/host.nix";
in
{
  options.nixosHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        config = lib.mkOption {
          type = lib.types.path;
          default = hostsDir + "/${name}/configuration.nix";
          description = "Path to the host's configuration.nix";
        };
        nixpkgs = lib.mkOption {
          type = lib.types.unspecified;
          default = inputs.nixpkgs;
          description = "Which nixpkgs flake to build the system from. Override per-host to match a vendor cache (e.g. nixos-raspberrypi).";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Where deploy-rs reaches this host. Bare hostnames resolve over the LAN's DNS; override if one can't.";
        };
      };
    }));
    default = {};
    description = "Mapping of hostname to NixOS configuration entrypoint";
  };

  config = {
    # Every field defaults off the directory name, so a host only needs a
    # host.nix when it deviates (eros builds from the rpi vendor nixpkgs).
    nixosHosts = lib.genAttrs hostNames (name:
      lib.optionalAttrs (builtins.pathExists (knobsFor name))
        (import (knobsFor name) { inherit inputs; }));

    flake.nixosConfigurations = lib.mapAttrs
      (name: host: myLib.mkSystem (host // { inherit name; }))
      config.nixosHosts;
  };
}
