{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {};
  config = {
    myNixOS.services.caddy.serviceMap = {
      jellyfin = {
        port = 8096;
      };
      jellyseerr = {
        port = 5055;
      };
      sonarr = {
        port = 8989;
      };
      radarr = {
        port = 7878;
      };
      prowlarr = {
        port = 9696;
      };
      bazarr = {
        port = 6767;
      };
    };
    environment.systemPackages = with pkgs; [
      tremc
    ];
    services.flaresolverr.enable = true;
    services.radarr.settings.auth.required = "DisabledForLocalAddresses";
    services.sonarr.settings.auth.required = "DisabledForLocalAddresses";
    services.prowlarr.settings.auth.required = "DisabledForLocalAddresses";
    nixarr = {
      enable = true;
      jellyfin = {
        enable = true;
        libraries = [
          {
            name = "tvshows";
            type = "tvshows";
            paths = ["/storage/downloads/tvshows" "${config.nixarr.mediaDir}/library/shows"];
            enable = true;
          }
          {
            name = "movies";
            type = "movies";
            paths = ["/storage/downloads/movies" "${config.nixarr.mediaDir}/library/movies"];
            enable = true;
          }
        ];
        users = [
          {
            name = "cramt";
            passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinCramtPassword;
            isAdministrator = true;
          }
          {
            name = "hannah";
            passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinHannahPassword;
            isAdministrator = true;
          }
        ];
      };
      jellyseerr.enable = true;
      bazarr.enable = true;
      sonarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };
      radarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };
      prowlarr = {
        enable = true;
        settings-sync = {
          enable-nixarr-apps = true;
        };
      };

      transmission = {
        enable = true;
      };
      mediaDir = "/storage/media";
      stateDir = "/storage/media/.state/nixarr";
    };

  };
}
