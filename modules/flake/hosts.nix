{ lib, config, myLib, inputs, ... }:
let
  hostsDir = ../../hosts;

  # hosts/ holds exactly the NixOS hosts — one directory each — so the fleet is
  # discovered rather than listed. Adding a machine is "make the folder".
  hostNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir hostsDir)
  );

  knobsFor = name: hostsDir + "/${name}/host.nix";

  # Resolved here rather than by peeking at other hosts' nixosConfigurations,
  # which would make every host evaluate every other host.
  buildPool = lib.mapAttrs
    (_: host: host.builder // { inherit (host) address; })
    (lib.filterAttrs (_: host: host.builder != null) config.nixosHosts);
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
        builder = lib.mkOption {
          type = lib.types.nullOr (lib.types.submodule {
            options = {
              maxJobs = lib.mkOption {
                type = lib.types.ints.positive;
                description = "Concurrent builds the rest of the pool may run here.";
              };
              speedFactor = lib.mkOption {
                type = lib.types.ints.positive;
                default = 1;
                description = "Relative per-job speed; Nix prefers the higher one among equally loaded builders.";
              };
              systems = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "x86_64-linux" ];
              };
              features = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
              };
              # Doubles as the client identity: the daemon (root) authenticates
              # with the host key, so there's no builder keypair to provision.
              hostKey = lib.mkOption {
                type = lib.types.str;
                default = lib.fileContents (hostsDir + "/${name}/ssh_host_ed25519_key.pub");
                description = "The host's ed25519 SSH host public key.";
              };
            };
          });
          default = null;
          description = "Join the build pool: offload builds to the other members and accept theirs. null = not a member.";
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
      (name: host: myLib.mkSystem (host // { inherit name buildPool; }))
      config.nixosHosts;
  };
}
