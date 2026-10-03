# Steam on ganymede, to try Remote Play from saturn's Steam next to Moonlight.
# The Steam client is X11 only and emrakul has no Xwayland, so Steam runs in
# gamescope nested as an ordinary Wayland client: gamescope brings its own
# Xwayland. Drop gamescope if emrakul ever gets Xwayland
# (xwayland-satellite, as niri does).
{
  config,
  lib,
  pkgs,
  ...
}: let
  steam = config.programs.steam.package;

  app = pkgs.writeShellApplication {
    name = "steam-home";
    text = ''
      # emrakul runs with only Home's apps as its data dir (home-apps.nix).
      export XDG_DATA_DIRS="/etc/profiles/per-user/$USER/share:/run/current-system/sw/share"
      # Steam decides it's in a gamescope session (SteamOS) from
      # GAMESCOPE_WAYLAND_DISPLAY, and then hides Exit Steam from its Power
      # menu for SteamOS's Switch to Desktop, which does nothing here. Without
      # it, Exit Steam is back, and gamescope exits with Steam, back to Home.
      exec ${lib.getExe pkgs.gamescope} -W 3840 -H 2160 -r 60 -f -e -- \
        env -u GAMESCOPE_WAYLAND_DISPLAY ${lib.getExe steam} -gamepadui
    '';
  };

  entry = pkgs.runCommand "steam-home-entry" {} ''
    install -Dm644 /dev/stdin $out/share/applications/steam-home.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Steam
    Exec=${lib.getExe app}
    Icon=steam-home
    X-Emrakul-Brand=#1b2838
    X-Emrakul-Controller=app
    X-Emrakul-Tv=game
    EOF
    install -Dm644 ${steam}/share/icons/hicolor/256x256/apps/steam.png \
      $out/share/icons/hicolor/256x256/apps/steam-home.png
  '';
in {
  programs.steam = {
    enable = true;
    # Remote Play's discovery and stream ports.
    remotePlay.openFirewall = true;
    # Steam lists audio devices through pactl; nothing else on the TV brings it.
    extraPackages = [pkgs.pulseaudio];
  };

  ganymede.homeApps = [entry];

  # emrakul's module locks the puck's hidraw to root, so nothing can make
  # hid-steam drop the gamepad. Steam Input needs exactly that hidraw, so give
  # it back to the seat's user: while Steam runs it owns the controller and
  # emrakul sees no gamepad, then emrakul picks it up again by hotplug once
  # Steam exits. Sorts after emrakul's 61- rule and before 73-seat-late.
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/62-ganymede-steam-hidraw.rules" ''
      SUBSYSTEM=="hidraw", KERNELS=="*:28DE:*", TAG+="uaccess", MODE="0660"
    '')
  ];
}
