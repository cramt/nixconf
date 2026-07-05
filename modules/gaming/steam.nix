# Steam gaming with Gamescope and GameMode
{ ... }: {
  flake.nixosModules."features.steam" = { config, lib, pkgs, ... }: {
    options.myNixOS.steam.enable = lib.mkEnableOption "myNixOS.steam";
    config = lib.mkIf config.myNixOS.steam.enable {
      programs.gamescope.enable = true;
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
      };
      environment.systemPackages = with pkgs; [
        mangohud
        steamcmd
      ];
      environment.sessionVariables = {
        STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
      };
      # Grant the logged-in session direct access to HOTAS/joystick raw-HID
      # nodes. evdev/js* nodes already get uaccess from logind's default
      # ID_INPUT_JOYSTICK rules, but the /dev/hidrawN node does not unless a
      # rule tags it — and Valve's steam-input rules only cover a handful of
      # Thrustmaster products. Without this, hidraw stays root-only, so Steam
      # Input and Proton's HID backend can't enumerate the stick (e.g. Ace
      # Combat 7 sees no HOTAS even though the kernel detects it).
      #
      # This MUST ship as a file numbered below 73 so it runs before
      # systemd's 73-seat-late.rules, which is where the `uaccess` tag is
      # turned into an ACL. services.udev.extraRules lands in 99-local.rules
      # (too late: the tag is set, but the ACL builtin already ran), hence a
      # dedicated 70- package here instead.
      services.udev.packages = [
        (pkgs.writeTextDir "lib/udev/rules.d/70-thrustmaster-hotas.rules" ''
          # Thrustmaster T.Flight Hotas X
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="044f", ATTRS{idProduct}=="b108", MODE="0660", TAG+="uaccess"
          # Broader Thrustmaster flight-gear coverage (T.16000M, TWCS, TCA, etc.)
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="044f", MODE="0660", TAG+="uaccess"
        '')
      ];

      programs.gamemode.enable = true;
      systemd.user.services.steam_background = {
        enable = true;
        description = "Open Steam in the background at boot";
        wantedBy = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = "${pkgs.steam}/bin/steam -nochatui -nofriendsui -silent %U";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  };
}
