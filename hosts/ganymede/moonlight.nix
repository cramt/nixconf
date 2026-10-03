# Moonlight on ganymede: paired with saturn's Sunshine ahead of time
# (modules/gaming/moonlight.nix), with any other PC by PIN from the Moonlight
# tile, and a Game on Home for every app every paired PC lists, found by
# emrakul-games (packages/emrakul-games, docs/moonlight-pairing.md). saturn's
# own apps come from hosts/saturn/games.nix, on its side.
# https://github.com/cramt/emrakul/issues/12, /16
{
  config,
  lib,
  pkgs,
  ...
}: let
  moonlight = lib.getExe pkgs.moonlight-qt;
  user = config.myNixOS.moonlight.user;
  logo = "${pkgs.moonlight-qt}/share/icons/hicolor/scalable/apps/moonlight.svg";

  # Both run as Home's apps do, so each puts the normal XDG_DATA_DIRS back
  # (home-apps.nix), and lets SDL read the controller the way a Game needs:
  # SDL's HIDAPI driver would open the controller's hidraw, and hid-steam
  # drops the gamepad node whenever anything does. With it off, SDL reads
  # the hid-steam evdev nodes that emrakul lets go of for the app.
  # https://github.com/cramt/emrakul/issues/5
  env = ''
    export XDG_DATA_DIRS="/etc/profiles/per-user/$USER/share:/run/current-system/sw/share"
    export SDL_JOYSTICK_HIDAPI=0
  '';

  # A Game: `moonlight-game <address> <app>`. The address, not the name: two
  # PCs here call themselves saturn (hosts/saturn/lan.nix), and Moonlight adds
  # whatever a name resolves to. --no-keep-awake: a game never holds the TV
  # awake (emrakul's Idle). --quit-after: ending the stream any other way
  # ends the app on the PC too.
  stream = pkgs.writeShellApplication {
    name = "moonlight-game";
    text = ''
      ${env}
      exec ${moonlight} stream "$1" "$2" \
        --display-mode fullscreen --resolution 3840x2160 --fps 60 \
        --no-keep-awake --quit-after
    '';
  };

  # `moonlight-game-quit <address>`: going Home ends the app on the PC this
  # way; killing the stream would leave it running there. Offscreen and
  # bounded: Home is already back on screen, and a failure's modal dialog
  # would otherwise sit over it (or, offscreen, wait forever) for someone to
  # dismiss.
  quit = pkgs.writeShellApplication {
    name = "moonlight-game-quit";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      QT_QPA_PLATFORM=offscreen exec timeout 30 ${moonlight} quit "$1"
    '';
  };

  discover = pkgs.writeShellApplication {
    name = "emrakul-games-discover";
    text = ''
      exec ${lib.getExe pkgs.emrakul-games} \
        --stream ${lib.getExe stream} \
        --quit ${lib.getExe quit} \
        --fallback-icon ${logo} \
        --state "''${XDG_STATE_HOME:-$HOME/.local/state}/emrakul-games"
    '';
  };

  # Moonlight's own window, for pairing another PC by PIN: it finds Sunshine
  # hosts on the LAN, and the controller drives it.
  gui = pkgs.writeShellApplication {
    name = "moonlight-home";
    text = ''
      ${env}
      exec ${moonlight} "$@"
    '';
  };
  guiEntry = pkgs.runCommand "moonlight-home-entry" {} ''
    install -Dm644 /dev/stdin $out/share/applications/moonlight-home.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Moonlight
    Exec=${lib.getExe gui}
    Icon=moonlight-home
    X-Emrakul-Brand=#565c64
    X-Emrakul-Controller=app
    EOF
    install -Dm644 ${logo} $out/share/icons/hicolor/scalable/apps/moonlight-home.svg
  '';

  conf = "%h/.config/Moonlight Game Streaming Project/Moonlight.conf";
in {
  myNixOS.moonlight = {
    enable = true;
    user = "cramt";
    host = import ../saturn/lan.nix;
    clientKey = "op://Homelab/Moonlight-ganymede/moonlight-ganymede.pem";
  };

  ganymede.homeApps = [guiEntry];

  # mDNS, for Moonlight's window to find a PC to pair: answers come back
  # multicast, which the firewall's connection tracking never matches to
  # Moonlight's query.
  networking.firewall.allowedUDPPorts = [5353];
  ganymede.homeStateDirs = ["emrakul-games"];

  # At session start, after the pairing is seeded; again whenever Moonlight
  # rewrites its conf (a PIN pairing, a host renamed or forgotten); and every
  # few minutes for apps added on a PC's side.
  systemd.user.services.emrakul-games = {
    description = "Home's Games, from every paired Sunshine host";
    wantedBy = ["graphical-session.target"];
    after = ["moonlight-pairing.service"];
    unitConfig = {
      ConditionUser = user;
      # Moonlight can rewrite its conf a few times in a row, and each write
      # starts this: the default start limit would mark it failed.
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe discover;
    };
  };
  systemd.user.paths.emrakul-games = {
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    unitConfig.ConditionUser = user;
    pathConfig.PathChanged = conf;
  };
  systemd.user.timers.emrakul-games = {
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    unitConfig.ConditionUser = user;
    timerConfig = {
      OnActiveSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}
