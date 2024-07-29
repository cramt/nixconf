{ config, lib, ... }:
let
  cfg = config.myNixOS.services.adguard;
  docker_versions = import ../../docker_versions.nix;
in
{
  options.myNixOS.services.adguard =
    {
      workVolume = lib.mkOption {
        type = lib.types.str;
        description = ''
          destination for adguards work volume
        '';
      };
      configVolume = lib.mkOption {
        type = lib.types.str;
        description = ''
          destination for adguards config volume
        '';
      };
    };
  config = {
    networking.firewall = {
      allowedUDPPorts = [ 553 ];
      allowedTCPPorts = [ 553 ];
    };
    virtualisation.oci-containers.containers.adguard = {
      hostname = "adguard";
      image = "adguard/adguardhome:${docker_versions.adguard}";
      volumes = [
        "${cfg.configVolume}:/opt/adguardhome/conf"
        "${cfg.workVolume}:/opt/adguardhome/work"
      ];
      ports = [
        "553:53/udp"
        "553:53/tcp"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=3000"
        "--expose=80"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
      };
      autoStart = true;
    };
  };
}
