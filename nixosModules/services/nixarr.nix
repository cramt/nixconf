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
    nixarr = {
      enable = true;
      jellyfin = {
        enable = true;
      };
      jellyseerr.enable = true;
      bazarr.enable = true;
      sonarr = {
        enable = true;
      };
      radarr = {
        enable = true;
      };
      prowlarr = {
        enable = true;
      };

      transmission = {
        enable = true;
      };
      mediaDir = "/storage/media";
      stateDir = "/storage/media/.state/nixarr";
    };
  };
}
