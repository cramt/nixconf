{pkgs, ...}: {
  options = {};
  config = {
    myNixOS.services.caddy.serviceMap = {
      jellyfin = 8096;
      jellyseerr = 5055;
      sonarr = 8989;
      radarr = 7878;
      prowlarr = 9696;
      bazarr = 6767;
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
        users = [
          {
            name = "testadmin";
            passwordFile = pkgs.writeText "password" "password123";
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
