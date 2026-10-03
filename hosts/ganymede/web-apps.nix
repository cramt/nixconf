# ganymede's web apps: what emrakul's Home lists. Each one is a browser
# opening one URL fullscreen, as a desktop entry with an icon and a brand
# colour that Home draws its tile from. YouTube and Nebula run in Firefox,
# for full uBlock Origin; Jellyfin runs in Chromium, for HEVC.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Monochrome brand glyphs from simple-icons, pinned to one commit. Home puts
  # the icon on a tile of the entry's X-Emrakul-Brand colour, so the glyph is
  # recoloured white to read on it.
  simpleIconsRev = "1089fb7d2bf0e323f834c205ab76265005a6d5e8";
  simpleIcon = slug: hash:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/simple-icons/simple-icons/${simpleIconsRev}/icons/${slug}.svg";
      inherit hash;
    };

  # emrakul runs with only Home's apps as its data dir (home-apps.nix).
  restoreDataDirs = ''
    export XDG_DATA_DIRS="/etc/profiles/per-user/$USER/share:/run/current-system/sw/share"
  '';

  # A profile per app keeps each one logged in on its own, and keeps one app's
  # leftover browser from swallowing another's launch.
  profileDir = id: ''"''${XDG_STATE_HOME:-$HOME/.local/state}/web-apps/${id}"'';

  # Firefox: `--kiosk` on the app's own profile. Policies (extensions,
  # permissions, nags) are system-wide, below. Prefs go in the profile's
  # user.js, which Firefox applies over its own prefs.js on every start, so
  # rewriting it each launch keeps the profile declarative.
  firefox = id: {
    url,
    prefs ? {},
  }: let
    userJs = pkgs.writeText "web-app-${id}-user.js" (lib.concatStrings (lib.mapAttrsToList
      (name: value: "user_pref(${builtins.toJSON name}, ${builtins.toJSON value});\n")
      (firefoxPrefs // prefs)));
  in
    pkgs.writeShellApplication {
      name = "web-app-${id}";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        ${restoreDataDirs}
        # nvidia-vaapi-driver's Firefox recipe:
        # https://github.com/elFarto/nvidia-vaapi-driver#firefox
        export LIBVA_DRIVER_NAME=nvidia
        export MOZ_DISABLE_RDD_SANDBOX=1
        profile=${profileDir id}
        mkdir -p "$profile"
        install -m644 ${userJs} "$profile/user.js"
        exec ${lib.getExe config.programs.firefox.finalPackage} --profile "$profile" --no-remote --kiosk ${lib.escapeShellArg url} "$@"
      '';
    };

  firefoxPrefs = {
    # NVIDIA is on Firefox's VA-API blocklist, so hardware decode has to be
    # forced. nvidia-vaapi-driver's direct backend (its default since 0.0.11)
    # does the rest.
    "media.hardware-video-decoding.force-enabled" = true;
    # The 1050 Ti (Pascal) has no AV1 decoder. With AV1 on, YouTube picks it
    # and Firefox decodes 4K60 on the CPU; off, it gets VP9 on NVDEC.
    "media.av1.enabled" = false;
    # Nothing modal: from the couch there's nothing to dismiss it with but
    # the trackpad.
    "browser.sessionstore.resume_from_crash" = false;
    "toolkit.startup.max_resumed_crashes" = -1;
    "browser.translations.enable" = false;
    "full-screen-api.warning.timeout" = 0;
  };

  # Chromium: `--app` in kiosk mode on the app's own profile.
  chromium = id: {
    url,
    flags ? [],
  }:
    pkgs.writeShellApplication {
      name = "web-app-${id}";
      runtimeInputs = [pkgs.chromium];
      text = ''
        ${restoreDataDirs}
        # The VA-API recipe measured in emrakul#14: 4K60 VP9 on NVDEC at ~26%
        # decoder load and ~23% CPU, against ~77% CPU decoding in software.
        # nvidia-vaapi-driver itself comes in through nixpkgs' nvidia module
        # (hardware.nvidia.videoAcceleration). Drop these flags once Chromium
        # picks VA-API on NVIDIA by default.
        # https://github.com/cramt/emrakul/issues/14
        export LIBVA_DRIVER_NAME=nvidia
        exec chromium \
          --user-data-dir=${profileDir id} \
          --ozone-platform=wayland \
          --kiosk --app=${lib.escapeShellArg url} \
          --no-first-run --noerrdialogs --password-store=basic \
          --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs \
          --ignore-gpu-blocklist --use-gl=angle --use-angle=gl \
          ${lib.escapeShellArgs flags} \
          "$@"
      '';
    };

  webApps = {
    youtube = {
      name = "YouTube";
      brand = "#ff0000";
      icon = simpleIcon "youtube" "sha256-UDiAisu8Tm7doWy+scxt7IDk5O5OIn4DnEEin6Iiqow=";
      # The TV UI goes back on Escape; Alt+Left would walk Firefox's history
      # under its router.
      back = "Escape";
      # youtube.com/tv, the 10-foot UI, only serves a console's user agent.
      # Cobalt 25, not 26: since mid-2026 a Cobalt/26 UA stops playback about
      # 45 s into every video (shy1132/VacuumTube#198, fixed there by going
      # back to 25 in #220). The override covers the whole profile, which is
      # this app's alone.
      # https://github.com/shy1132/VacuumTube/issues/198
      exe = firefox "youtube" {
        url = "https://www.youtube.com/tv";
        prefs = {
          "general.useragent.override" = "Mozilla/5.0 (PS4; Leanback Shell) Cobalt/25.lts.40.1035033; compatible;";
          # The TV UI sends Widevine-encrypted streams to Cobalt above 19,
          # and without EME most videos stop at "This video format is not
          # supported" (shy1132/VacuumTube#83). Firefox fetches Google's CDM
          # into the profile on first use. The CDM decodes on the CPU, not
          # NVDEC: drop this once the TV UI plays in the clear again.
          # https://github.com/shy1132/VacuumTube/issues/83
          "media.eme.enabled" = true;
          "media.gmp-widevinecdm.enabled" = true;
          "media.gmp-widevinecdm.visible" = true;
        };
      };
    };
    nebula = {
      name = "Nebula";
      brand = "#2cadfe";
      icon = simpleIcon "nebula" "sha256-vLf23V7upziCBcP1xW56TGySZuwnD2QCETDOc6IHChs=";
      exe = firefox "nebula" {url = "https://nebula.tv";};
    };
    jellyfin = {
      name = "Jellyfin";
      brand = "#00a4dc";
      icon = simpleIcon "jellyfin" "sha256-JE1rGRNRiRQKz/b4wceTejBkkStIIpq3Xyb343Eku5I=";
      # Escape is back in Jellyfin's TV layout.
      back = "Escape";
      exe = chromium "jellyfin" {
        url = "https://jellyfin.cramt.dk";
        # Jellyfin's TV layout (focus navigation on the arrows) comes on by
        # itself when its browser detection sees "tv" in the user agent:
        # https://github.com/jellyfin/jellyfin-web/blob/master/src/scripts/browser.js
        # Chromium's own UA plus that token keeps `browser.chrome`, so the
        # device profile (HEVC, AV1, ...) is still probed from what Chromium
        # can play. The only other choice is seeding localStorage.layout,
        # which nothing in Chromium can do declaratively.
        flags = ["--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${lib.versions.major pkgs.chromium.version}.0.0.0 Safari/537.36 SmartTV"];
      };
    };
  };

  entry = id: app:
    pkgs.runCommand "web-app-${id}-entry" {} ''
      install -Dm644 /dev/stdin $out/share/applications/web-app-${id}.desktop <<EOF
      [Desktop Entry]
      Type=Application
      Name=${app.name}
      Exec=${lib.getExe app.exe}
      Icon=web-app-${id}
      X-Emrakul-Brand=${app.brand}
      ${lib.optionalString (app ? back) "X-Emrakul-Back=${assert lib.assertOneOf "back" app.back ["Alt+Left" "Escape"]; app.back}"}
      EOF
      mkdir -p $out/share/icons/hicolor/scalable/apps
      sed 's|<svg |<svg fill="#ffffff" |' ${app.icon} > $out/share/icons/hicolor/scalable/apps/web-app-${id}.svg
    '';
in {
  ganymede.homeApps = lib.mapAttrsToList entry webApps;

  programs.firefox = {
    enable = true;
    policies = {
      # Fetched from AMO on a profile's first start; Firefox keeps them updated.
      # SponsorBlock opens its welcome page as the visible tab on that first
      # start (it has no managed setting to skip it); going Home and back
      # leaves it behind for good.
      # Full uBlock Origin is why YouTube and Nebula are on Firefox: its
      # response-rewriting filters need webRequest.filterResponseData, which
      # Chromium's MV3 extensions don't get.
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "sponsorBlocker@ajay.app" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
          installation_mode = "force_installed";
        };
      };
      Permissions = {
        Notifications = {
          BlockNewRequests = true;
          Locked = true;
        };
        Location = {
          BlockNewRequests = true;
          Locked = true;
        };
      };
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DontCheckDefaultBrowser = true;
      OfferToSaveLogins = false;
      PasswordManagerEnabled = false;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        UrlbarInterventions = false;
        SkipOnboarding = true;
        MoreFromMozilla = false;
        FirefoxLabs = false;
        Locked = true;
      };
    };
  };

  programs.chromium = {
    enable = true;
    # Anything modal is a dead end from the couch: there is no pointer to
    # dismiss it with but the trackpad.
    extraOpts = {
      PasswordManagerEnabled = false;
      TranslateEnabled = false;
      DefaultBrowserSettingEnabled = false;
      PromotionsEnabled = false;
      BrowserSignin = 0;
      RestoreOnStartup = 5; # open the --app URL, never the last session
      DefaultNotificationsSetting = 2; # never ask, never show
      DefaultGeolocationSetting = 2;
    };
  };
}
