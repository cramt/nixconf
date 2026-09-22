{inputs, ...}: {
  flake.nixosModules."services.nixarr" = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.myNixOS.services.nixarr;
    jellarrPkg = inputs.jellarr.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
        shelfmark = {
          port = 8084;
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
          # luna has a GeForce GTX 1660 (TU116, Turing) — transcode on NVENC/NVDEC
          # instead of pegging the CPU with libx264. Jellyfin defaults hw accel
          # to "none", so set it declaratively here.
          # Turing NVENC = H.264 + HEVC; NVDEC = H.264/HEVC/VC1/VP8/VP9. No AV1
          # encode or decode on this GPU (Ampere/Ada only), so it's left off the
          # lists and AV1 stays software.
          encoding = {
            enableHardwareEncoding = true;
            hardwareAccelerationType = "nvenc";
            allowHevcEncoding = true;
            hardwareDecodingCodecs = ["h264" "hevc" "vc1" "vp8" "vp9"];
            enableDecodingColorDepth10Hevc = true;
            enableDecodingColorDepth10Vp9 = true;
          };
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
                  {path = "${config.nixarr.mediaDir}/library/shows";}
                ];
              }
              {
                name = "movies";
                collectionType = "movies";
                libraryOptions.pathInfos = [
                  {path = "${config.nixarr.mediaDir}/library/movies";}
                ];
              }
              {
                name = "books";
                collectionType = "books";
                libraryOptions.pathInfos = [
                  {path = "${config.nixarr.mediaDir}/library/books";}
                ];
              }
            ];
          };
        };
      };

      # Shelfmark searches through Prowlarr rather than keeping its own indexer
      # list, so Prowlarr stays the single registry -- the 18 indexers it already
      # syncs to sonarr/radarr serve books too. It is a search-and-grab tool, not
      # an *arr: no author monitoring, no quality profiles. Readarr, the actual
      # Sonarr-for-books, was retired upstream and its metadata servers are gone.
      services.shelfmark.environment = {
        PROWLARR_ENABLED = "true";
        PROWLARR_URL = "http://127.0.0.1:9696";
        # Naming the client is what registers it; TRANSMISSION_URL alone leaves
        # shelfmark reporting "No download clients configured" and erroring
        # every grab.
        PROWLARR_TORRENT_CLIENT = "transmission";
        TRANSMISSION_URL = "http://127.0.0.1:9091";
        TRANSMISSION_CATEGORY = "books";
        INGEST_DIR = "${config.nixarr.mediaDir}/library/books";
        # Open Library is the one metadata provider needing no API key, so it
        # stays fully declarative; Hardcover and Google Books would each add a
        # secret to carry for no gain here.
        OPENLIBRARY_ENABLED = "true";
        # Reading happens on a kindle, not in jellyfin, so azw3 and mobi are
        # first-class here rather than something to filter out. This drops the
        # rest of the default list -- fb2 and djvu the kindle will not read, and
        # cbz/cbr are comics, not books. pdf is absent from the default and
        # stays excluded either way: unreadable on a kindle.
        SUPPORTED_FORMATS = "epub,azw3,mobi";
      };

      # Prowlarr generates its own API key into its state dir, so lifting it into
      # 1Password would mean two copies to keep in step. Read it at activation
      # instead: Prowlarr remains the one source, and the key never enters the
      # world-readable store the way services.shelfmark.environment would.
      systemd.services.shelfmark.serviceConfig = {
        EnvironmentFile = "-/run/shelfmark/prowlarr.env";
        ExecStartPre = lib.mkBefore [
          "+${pkgs.writeShellScript "shelfmark-prowlarr-key" ''
            set -euo pipefail
            key=$(${pkgs.gnused}/bin/sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' \
              ${config.nixarr.stateDir}/prowlarr/config.xml)
            install -d -m 0700 /run/shelfmark
            umask 077
            printf 'PROWLARR_API_KEY=%s\n' "$key" > /run/shelfmark/prowlarr.env
          ''}"
        ];
      };

      nixarr = {
        enable = true;
        shelfmark.enable = true;
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
        mediaDir = lib.mkDefault "/pool/media";
        stateDir = lib.mkDefault "/pool/media/.state/nixarr";
      };

      # jellarr's NixOS module rebuilds its package against the consumer's
      # pkgs, which fails when nixpkgs has moved past the pnpmDeps hash the
      # upstream flake locked. Use the package built with jellarr's own pinned
      # nixpkgs instead.
      systemd.services.jellarr.serviceConfig.ExecStart =
        lib.mkForce (lib.getExe jellarrPkg);
    };
  };
}
