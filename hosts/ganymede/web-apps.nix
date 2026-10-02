# ganymede's web apps: what emrakul's Home lists. Each one is Chromium opening
# one URL fullscreen, as a desktop entry with an icon and a brand colour that
# Home draws its tile from.
{
  lib,
  options,
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

  webApps = {
    youtube = {
      name = "YouTube";
      # The regular site, not youtube.com/tv: the TV UI is deprecated and the
      # desktop site is what does 4K60 with hardware decode here.
      url = "https://www.youtube.com";
      brand = "#ff0000";
      icon = simpleIcon "youtube" "sha256-UDiAisu8Tm7doWy+scxt7IDk5O5OIn4DnEEin6Iiqow=";
    };
    nebula = {
      name = "Nebula";
      url = "https://nebula.tv";
      brand = "#2cadfe";
      icon = simpleIcon "nebula" "sha256-vLf23V7upziCBcP1xW56TGySZuwnD2QCETDOc6IHChs=";
    };
    jellyfin = {
      name = "Jellyfin";
      url = "https://jellyfin.cramt.dk";
      brand = "#00a4dc";
      icon = simpleIcon "jellyfin" "sha256-JE1rGRNRiRQKz/b4wceTejBkkStIIpq3Xyb343Eku5I=";
    };
  };

  # The VA-API recipe measured in emrakul#14: 4K60 VP9 on NVDEC at ~26%
  # decoder load and ~23% CPU, against ~77% CPU decoding in software.
  # nvidia-vaapi-driver itself comes in through nixpkgs' nvidia module
  # (hardware.nvidia.videoAcceleration). Drop these flags once Chromium picks
  # VA-API on NVIDIA by default.
  # https://github.com/cramt/emrakul/issues/14
  launcher = id: app:
    pkgs.writeShellApplication {
      name = "web-app-${id}";
      runtimeInputs = [pkgs.chromium];
      text = ''
        export LIBVA_DRIVER_NAME=nvidia
        # emrakul runs with only the web apps as its data dir (see below).
        export XDG_DATA_DIRS="/etc/profiles/per-user/$USER/share:/run/current-system/sw/share"
        # A profile per app keeps each one logged in on its own, and keeps one
        # app's leftover Chromium from swallowing another's launch.
        # --force-device-scale-factor=2: emrakul advertises scale 1, so pages
        # would render at 1x on a 4K TV, unreadable from the couch. 2x is
        # 1080p-sized CSS. Drop once emrakul sends a scale for the TV.
        exec chromium \
          --user-data-dir="''${XDG_STATE_HOME:-$HOME/.local/state}/web-apps/${id}" \
          --ozone-platform=wayland \
          --kiosk --app=${lib.escapeShellArg app.url} \
          --no-first-run --noerrdialogs --password-store=basic \
          --force-device-scale-factor=2 \
          --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs \
          --ignore-gpu-blocklist --use-gl=angle --use-angle=gl \
          "$@"
      '';
    };

  entry = id: app: let
    exe = launcher id app;
  in
    pkgs.runCommand "web-app-${id}-entry" {} ''
      install -Dm644 /dev/stdin $out/share/applications/web-app-${id}.desktop <<EOF
      [Desktop Entry]
      Type=Application
      Name=${app.name}
      Exec=${lib.getExe exe}
      Icon=web-app-${id}
      X-Emrakul-Brand=${app.brand}
      EOF
      mkdir -p $out/share/icons/hicolor/scalable/apps
      sed 's|<svg |<svg fill="#ffffff" |' ${app.icon} > $out/share/icons/hicolor/scalable/apps/web-app-${id}.svg
    '';
  webAppsPackage = pkgs.symlinkJoin {
    name = "web-apps";
    paths = lib.mapAttrsToList entry webApps;
  };
in {
  # Home lists every desktop entry in XDG_DATA_DIRS, and the system and home
  # profiles carry plenty (nvim, btop, qt5ct, nixos-manual, ...). The TV shows
  # only the web apps, so emrakul gets a data dir holding nothing else. Its
  # unit's Environment= can't do this: PAM's login stack sets XDG_DATA_DIRS
  # after it. The launchers put the normal dirs back for Chromium.
  services.emrakul.package = let
    emrakul = options.services.emrakul.package.default;
  in
    pkgs.writeShellApplication {
      name = "emrakul";
      text = ''
        XDG_DATA_DIRS=${webAppsPackage}/share exec ${lib.getExe emrakul} "$@"
      '';
    };

  programs.chromium = {
    enable = true;
    # ExtensionInstallForcelist: Chromium fetches these from the Web Store on
    # first start of each profile and keeps them updated itself.
    extensions = [
      "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
      "mnjggcdmjocbbbhaepdhchncahnbgone" # SponsorBlock
    ];
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
