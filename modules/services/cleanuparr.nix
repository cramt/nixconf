# Sonarr/Radarr park a release forever when the import check trips (e.g. a fake
# release whose "episode" is an .exe) — there is no built-in setting to remove
# and blocklist it, by design. Cleanuparr's Malware Blocker watches the queue,
# matches the download's files against a blacklist, then removes it from the
# torrent client, blocklists the release in the *arr, and kicks off a new search.
#
# Host networking because it talks to sonarr/radarr/transmission on localhost.
# Everything past that (clients, *arr URLs + API keys, the blacklist) is
# configured in its own web UI and lives in the data volume — the upstream
# project has no file-based config to declare.
{...}: {
  flake.nixosModules."services.cleanuparr" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.cleanuparr;
    port = config.port-selector.ports.cleanuparr;
  in {
    options.myNixOS.services.cleanuparr = {
      enable = lib.mkEnableOption "myNixOS.services.cleanuparr";
      dataVolume = lib.mkOption {
        type = lib.types.str;
        description = ''
          destination for the config and its database
        '';
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          open the web UI port. There is no reverse proxy entry for it: the UI
          holds every *arr API key and ships no auth, so keep it on the LAN.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      port-selector.set-ports."11011" = "cleanuparr";

      virtualisation.oci-containers.containers.cleanuparr = {
        hostname = "cleanuparr";
        image = "ghcr.io/cleanuparr/cleanuparr:2.10.5";
        volumes = ["${cfg.dataVolume}:/config"];
        environment = {
          PORT = builtins.toString port;
          TZ = config.time.timeZone;
        };
        extraOptions = ["--network=host"];
        autoStart = true;
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [port];
    };
  };
}
