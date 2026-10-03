# KDE Connect: text sent from the phone lands on emrakul's clipboard, for
# Ctrl+V (or the on-screen keyboard's Paste) in a web app, and Home gets a
# tile for kdeconnect-app. https://github.com/cramt/emrakul/issues/27
{
  config,
  lib,
  pkgs,
  ...
}: let
  kdeconnect = config.programs.kdeconnect.package;

  app = pkgs.writeShellApplication {
    name = "kdeconnect-app-home";
    text = ''
      # emrakul runs with only Home's apps as its data dir (home-apps.nix).
      export XDG_DATA_DIRS="/etc/profiles/per-user/$USER/share:/run/current-system/sw/share"
      exec ${kdeconnect}/bin/kdeconnect-app "$@"
    '';
  };

  # The tray glyph rather than the app icon: it's monochrome, so it can be
  # turned white for the brand tile like the web apps' simple-icons.
  entry = pkgs.runCommand "kdeconnect-home-entry" {} ''
    install -Dm644 /dev/stdin $out/share/applications/kdeconnect-home.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=KDE Connect
    Exec=${lib.getExe app}
    Icon=kdeconnect-home
    X-Emrakul-Brand=#3daee9
    EOF
    mkdir -p $out/share/icons/hicolor/scalable/apps
    sed 's/fill:#000000/fill:#ffffff/g' \
      ${kdeconnect}/share/icons/hicolor/scalable/apps/kdeconnectindicator.svg \
      > $out/share/icons/hicolor/scalable/apps/kdeconnect-home.svg
  '';
in {
  # Also opens TCP and UDP 1714-1764 for discovery, pairing and transfers.
  programs.kdeconnect.enable = true;

  ganymede.homeApps = [entry];

  # kdeconnectd normally comes up through XDG autostart, which emrakul doesn't
  # run. emrakul's module starts graphical-session.target once the compositor
  # is up, with WAYLAND_DISPLAY handed to the user manager, and the clipboard
  # plugin needs that connection: it reads and writes through data-control.
  systemd.user.services.kdeconnectd = {
    description = "KDE Connect daemon";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    serviceConfig = {
      ExecStart = "${kdeconnect}/bin/kdeconnectd";
      # Qt exits when its compositor goes away, and emrakul restarts itself.
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
