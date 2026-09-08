# Sonarr ranks releases by quality alone until custom formats exist. With none
# configured it grabbed a Japanese+Italian Netflix rip of a simulcast whose
# Crunchyroll dual-audio release was sitting on the same indexers with a tenth
# the seeders -- nothing in the profile expressed "the dub is the point".
#
# Recyclarr syncs the TRaSH Guides custom formats and an Anime quality profile
# into Sonarr on a timer, so that scoring is declared here instead of clicked
# into the Sonarr UI and lost on the next state-dir wipe.
{...}: {
  flake.nixosModules."services.recyclarr" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.recyclarr;
    credDir = "/run/recyclarr-credentials";
    apiKeyFile = "${credDir}/sonarr-api-key";
  in {
    options.myNixOS.services.recyclarr = {
      enable = lib.mkEnableOption "myNixOS.services.recyclarr";
      profileName = lib.mkOption {
        type = lib.types.str;
        default = "Anime";
        description = ''
          Sonarr quality profile that recyclarr creates and scores. Series that
          should only ever be grabbed with an English dub go on this profile.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # Sonarr mints its own API key into config.xml on first start, so there is
      # no authoritative copy to put in 1Password -- a second copy there would
      # just drift the first time the key is regenerated. Derive the credential
      # from the file that already exists. Runs as root because the nixarr state
      # dir is 0700 sonarr.
      systemd.services.recyclarr-sonarr-apikey = {
        description = "Extract Sonarr's API key for recyclarr";
        after = ["sonarr.service"];
        before = ["recyclarr.service"];
        requiredBy = ["recyclarr.service"];
        serviceConfig = {
          Type = "oneshot";
          RuntimeDirectory = "recyclarr-credentials";
          RuntimeDirectoryMode = "0700";
          # The oneshot exits before recyclarr starts; without this systemd
          # removes the directory out from under LoadCredential.
          RuntimeDirectoryPreserve = true;
          UMask = "0077";
        };
        script = ''
          ${lib.getExe pkgs.gnugrep} -oP '(?<=<ApiKey>)[^<]+' \
            ${config.nixarr.stateDir}/sonarr/config.xml > ${apiKeyFile}
        '';
      };

      systemd.services.recyclarr.after = ["sonarr.service" "network-online.target"];
      systemd.services.recyclarr.wants = ["network-online.target"];

      services.recyclarr = {
        enable = true;
        schedule = "daily";
        configuration.sonarr.main = {
          base_url = "http://localhost:8989";
          api_key._secret = apiKeyFile;

          quality_definition.type = "anime";

          quality_profiles = [
            {
              name = cfg.profileName;
              # Anything already scored by hand in the UI gets zeroed, so this
              # file stays the only thing that decides what wins.
              reset_unmatched_scores.enabled = true;
              # The floor is the whole point: a release has to match Anime Dual
              # Audio or Dubs Only to score above zero, so a subs-only rip is
              # not merely outranked, it is unpickable.
              min_format_score = 1;
              upgrade = {
                allowed = true;
                until_quality = "WEB 1080p";
                until_score = 10000;
              };
              qualities = [
                {
                  name = "WEB 1080p";
                  qualities = ["WEBDL-1080p" "WEBRip-1080p"];
                }
                {name = "Bluray-1080p";}
                {
                  name = "WEB 720p";
                  qualities = ["WEBDL-720p" "WEBRip-720p"];
                }
              ];
            }
          ];

          custom_formats = [
            {
              # Japanese audio + English audio in one release: the CR simulcast
              # rips. Preferred over a dub-only encode because the sub track is
              # still there when someone wants it.
              trash_ids = ["418f50b10f1907201b6cfdf881f467b7"]; # Anime Dual Audio
              assign_scores_to = [
                {
                  name = cfg.profileName;
                  score = 2000;
                }
              ];
            }
            {
              trash_ids = ["9c14d194486c4014d422adc64092d794"]; # Dubs Only
              assign_scores_to = [
                {
                  name = cfg.profileName;
                  score = 1500;
                }
              ];
            }
            {
              # Both of these push a release below min_format_score on their
              # own, so a bad group cannot ride in on a dual-audio tag.
              trash_ids = [
                "e3515e519f3b1360cbfc17651944354c" # Anime LQ Groups
                "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
              ];
              assign_scores_to = [
                {
                  name = cfg.profileName;
                  score = -10000;
                }
              ];
            }
          ];
        };
      };
    };
  };
}
