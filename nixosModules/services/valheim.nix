{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myNixOS.services.valheim;
  odinsrc =
    ((import ../../_sources/generated.nix) {
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub dockerTools;
    })
    .odin
    .src;
  odin = pkgs.rustPlatform.buildRustPackage {
    name = "odin";
    src = odinsrc;
    buildAndTestSubdir = "src/odin";
    cargoLock = {
      lockFile = "${odinsrc}/Cargo.lock";
    };
    buildInputs = [
      pkgs.steamcmd
    ];
  };
in {
  options.myNixOS.services.valheim = {
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        config volume mount
      '';
    };
    binaryVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        binary volume mount
      '';
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      description = ''
        server name
      '';
    };

    worldName = lib.mkOption {
      type = lib.types.str;
      description = ''
        world name
      '';
    };
  };
  config = {
    networking.firewall = {
      allowedUDPPorts = [2456 2457];
      allowedTCPPorts = [2456 2457];
    };

    environment.systemPackages = [odin];
  };
}
