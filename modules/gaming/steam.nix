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
        # Declarative GE-Proton: symlinked into compatibilitytools.d, shows up
        # as a compat tool in Steam's per-game "Force compatibility" dropdown.
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
      environment.systemPackages = with pkgs; [
        mangohud
        steamcmd
      ];
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
        # wantedBy alone only says "pull this in with the target", not "start it
        # after the target is reached" — so Steam raced the compositor and lost.
        # XOpenDisplay returned NULL, Steam handed that straight to
        # glXQueryExtension without checking, and it segfaulted in
        # XQueryExtension ~3s into every boot. It survived a manual start into
        # an already-warm session, which is what made it look intermittent.
        after = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        serviceConfig = {
          # Ordering alone relies on graphical-session.target implying a
          # *usable* X display, which isn't something the target actually
          # promises — XWayland comes up on the compositor's schedule. So assert
          # the real precondition instead of assuming it, since Steam's response
          # to not having one is to segfault rather than to complain.
          ExecStartPre = "${pkgs.bash}/bin/bash -c 'for _ in $(${pkgs.coreutils}/bin/seq 60); do ${pkgs.xorg.xdpyinfo}/bin/xdpyinfo >/dev/null 2>&1 && exit 0; ${pkgs.coreutils}/bin/sleep 1; done; exit 1'";
          # No %U here: that's a .desktop Exec specifier meaning "URLs", but
          # systemd expands %U to the UID, so Steam was being launched as
          # `steam ... -silent 1000` with a stray argument.
          ExecStart = "${pkgs.steam}/bin/steam -nochatui -nofriendsui -silent";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    };
  };
}
