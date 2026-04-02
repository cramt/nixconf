{...}: {
  flake.nixosModules."services.nixarr" = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.myNixOS.services.nixarr;
  in {
    options.myNixOS.services.nixarr = {
      enable = lib.mkEnableOption "myNixOS.services.nixarr";
    };
    config = lib.mkIf cfg.enable {
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

      services.jellarr = {
        enable = true;
        config = {
          version = 1;
          base_url = "http://localhost:8096";
          system = {};
          startup = {
            serverName = "luna-jellyfin";
            preferredMetadataLanguage = "en";
            metadataCountryCode = "DK";
            uiCulture = "en-US";
            remoteAccess = {
              enableRemoteAccess = true;
              enableAutomaticPortMapping = false;
            };
            user = {
              name = "cramt";
              passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinCramtPassword;
            };
            apiKeyApp = "jellarr";
            apiKeyFile = "${config.services.jellarr.dataDir}/api-key";
            completeStartupWizard = true;
          };
          users = [
            {
              name = "cramt";
              passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinCramtPassword;
              policy = {
                isAdministrator = true;
              };
            }
            {
              name = "hannah";
              passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinHannahPassword;
              policy = {
                isAdministrator = true;
              };
            }
          ];
          library = {
            virtualFolders = [
              {
                name = "tvshows";
                collectionType = "tvshows";
                libraryOptions.pathInfos = [
                  {path = "/storage/downloads/tvshows";}
                  {path = "${config.nixarr.mediaDir}/library/shows";}
                ];
              }
              {
                name = "movies";
                collectionType = "movies";
                libraryOptions.pathInfos = [
                  {path = "/storage/downloads/movies";}
                  {path = "${config.nixarr.mediaDir}/library/movies";}
                ];
              }
            ];
          };
        };
      };

      nixarr = {
        enable = true;
        jellyfin.enable = true;
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
        mediaDir = lib.mkDefault "/storage/media";
        stateDir = lib.mkDefault "/storage/media/.state/nixarr";
      };
    };
  };
}
