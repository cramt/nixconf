{ config, lib, ... }:
let

  cfg = config.myNixOS.services.jellyfin;
in
{
  options.myNixOS.services.jellyfin = {
    mediaVolumes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = ''
        destination for the jellyfin media files
      '';
    };
    configVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the jellyfin mutable config
      '';
    };
    gpuDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        gpu devices to pass to jellyfin
      '';
    };
  };
  config = {
    virtualisation.podman.enableNvidia = true;
    virtualisation.oci-containers.containers.jellyfin = {
      hostname = "jellyfin";
      image = "lscr.io/linuxserver/jellyfin";
      volumes = (
        lib.attrsets.mapAttrsToList
          (
            name: value: "${value}:/data/${name}"
          )
          cfg.mediaVolumes
      ) ++ [ "${cfg.configVolume}:/config" ];
      extraOptions = [
        "--network=caddy"
        "--expose=8096"
      ] ++ builtins.map (d: "--device=${d}:${d}") cfg.gpuDevices;
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
      };
      autoStart = true;
    };
  };
}
