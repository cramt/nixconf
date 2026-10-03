# Moonlight on ganymede: paired with saturn's Sunshine ahead of time
# (modules/gaming/moonlight.nix), and a Home tile streaming saturn's Desktop.
# https://github.com/cramt/emrakul/issues/12, /16
{
  config,
  lib,
  pkgs,
  ...
}: let
  saturn = import ../saturn/lan.nix;
  moonlight = lib.getExe pkgs.moonlight-qt;

  stream = pkgs.writeShellApplication {
    name = "moonlight-saturn-desktop";
    text = ''
      # emrakul runs with only Home's apps as its data dir (home-apps.nix).
      export XDG_DATA_DIRS="/etc/profiles/per-user/$USER/share:/run/current-system/sw/share"
      # SDL's HIDAPI driver would open the controller's hidraw, and hid-steam
      # drops the gamepad node whenever anything does. With it off, SDL reads
      # the hid-steam evdev nodes that emrakul lets go of for this app.
      # https://github.com/cramt/emrakul/issues/5
      export SDL_JOYSTICK_HIDAPI=0
      # --no-keep-awake: a game never holds the TV awake (emrakul's Idle).
      # The address, not the name: saturn.fritz.box also resolves to another
      # PC (lan.nix), and Moonlight adds whatever the name resolves to.
      # --quit-after: ending the stream any other way ends Desktop on saturn too.
      exec ${moonlight} stream ${saturn.address} Desktop \
        --display-mode fullscreen --resolution 3840x2160 --fps 60 \
        --no-keep-awake --quit-after
    '';
  };

  # Going Home ends Desktop on saturn this way; killing the stream would leave
  # it running there. Offscreen and bounded: Home is already back on screen,
  # and a failure's modal dialog would otherwise sit over it (or, offscreen,
  # wait forever) for someone to dismiss.
  quit = pkgs.writeShellApplication {
    name = "moonlight-saturn-quit";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      QT_QPA_PLATFORM=offscreen exec timeout 30 ${moonlight} quit ${saturn.address}
    '';
  };

  entry = pkgs.runCommand "moonlight-saturn-home-entry" {} ''
    install -Dm644 /dev/stdin $out/share/applications/moonlight-saturn-desktop.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Saturn
    Exec=${lib.getExe stream}
    Icon=moonlight-saturn
    X-Emrakul-Brand=#565c64
    X-Emrakul-Quit=${lib.getExe quit}
    X-Emrakul-Tv=game
    X-Emrakul-Controller=app
    EOF
    # Moonlight's own logo; its outer ring is the brand colour, so on the
    # tile it reads as the white disc and star.
    install -Dm644 ${pkgs.moonlight-qt}/share/icons/hicolor/scalable/apps/moonlight.svg \
      $out/share/icons/hicolor/scalable/apps/moonlight-saturn.svg
  '';
in {
  myNixOS.moonlight = {
    enable = true;
    user = "cramt";
    host = saturn;
    clientKey = "op://Homelab/Moonlight-ganymede/moonlight-ganymede.pem";
  };

  ganymede.homeApps = [entry];
}
