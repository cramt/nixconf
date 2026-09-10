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

    # Release titles are a claim, not evidence. A "DUAL" tag got us a file whose
    # only audio tracks were Portuguese and Japanese, because TRaSH's Bad Dual
    # Groups rule anchors on the parsed release group (^(BiOMA)$) and the
    # indexer had appended [EZTVx.to], so the -10000 never landed. Custom
    # formats cannot see inside the container; ffprobe can.
    dubGuard = pkgs.writeShellApplication {
      name = "sonarr-dub-guard";
      runtimeInputs = with pkgs; [curl jq ffmpeg gnugrep coreutils];
      text = ''
        sonarr="http://localhost:8989"
        api_key="$(cat ${apiKeyFile})"
        api() { curl -sf -m 60 -H "X-Api-Key: $api_key" "$@"; }

        profile_id="$(api "$sonarr/api/v3/qualityprofile" \
          | jq -r --arg n ${lib.escapeShellArg cfg.profileName} \
              '.[] | select(.name == $n) | .id')"
        if [ -z "$profile_id" ]; then
          echo "quality profile ${cfg.profileName} does not exist yet; nothing to guard"
          exit 0
        fi

        searched=""
        while read -r series_id; do
          [ -n "$series_id" ] || continue
          while IFS=$'\t' read -r ep_id file_id path; do
            [ -n "$path" ] && [ -f "$path" ] || continue
            if ffprobe -v error -select_streams a \
                 -show_entries stream_tags=language -of csv=p=0 "$path" \
                 2>/dev/null | grep -qx eng; then
              continue
            fi
            echo "no English audio track: $path"

            # Blocklist the grab first so the re-search cannot pick the same
            # lying release straight back off the same indexer.
            grab_id="$(api "$sonarr/api/v3/history?episodeId=$ep_id&eventType=1&pageSize=20&sortKey=date&sortDirection=descending" \
              | jq -r '.records[0].id // empty')"
            if [ -n "$grab_id" ]; then
              api -X POST -H "Content-Type: application/json" -d '{}' \
                "$sonarr/api/v3/history/failed/$grab_id" >/dev/null || true
            fi
            api -X DELETE "$sonarr/api/v3/episodefile/$file_id" >/dev/null || true
            searched="$searched $ep_id"
          done < <(api "$sonarr/api/v3/episode?seriesId=$series_id&includeEpisodeFile=true" \
            | jq -r '.[] | select(.hasFile) | "\(.id)\t\(.episodeFileId)\t\(.episodeFile.path)"')
        done < <(api "$sonarr/api/v3/series" \
          | jq -r --argjson p "$profile_id" '.[] | select(.qualityProfileId == $p) | .id')

        if [ -n "$searched" ]; then
          # shellcheck disable=SC2086
          jq -nc --args '{name: "EpisodeSearch", episodeIds: ($ARGS.positional | map(tonumber))}' $searched \
            | api -X POST -H "Content-Type: application/json" -d @- \
                "$sonarr/api/v3/command" >/dev/null
          echo "requeued a search for episodes:$searched"
        else
          echo "every file on the ${cfg.profileName} profile has an English audio track"
        fi
      '';
    };
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

      systemd.services.sonarr-dub-guard = {
        description = "Drop anime files whose audio tracks have no English";
        after = ["sonarr.service" "recyclarr-sonarr-apikey.service"];
        requires = ["recyclarr-sonarr-apikey.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe dubGuard;
        };
      };

      systemd.timers.sonarr-dub-guard = {
        description = "Periodic English-audio check on imported anime";
        wantedBy = ["timers.target"];
        timerConfig = {
          # Hourly rather than daily: a simulcast episode that imports wrong at
          # 02:00 should be re-grabbed before anyone sits down to watch it.
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
      };

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
