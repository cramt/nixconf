# Living-room console: Steam's gamescope session as the entire shell.
#
# This deliberately has no custom launcher. eros ran a wofi picker in a
# supervisor loop with the Steam Controller in Bluetooth "lizard mode" (pad as a
# HID mouse) because a Pi can't run Steam — every bit of that was reimplementing
# Steam Input by hand. On x86 the controller is first-class Valve hardware:
# Big Picture is already a 10-foot UI, and Steam Input gives per-app control
# layouts, so the browser and the media player get real controller mappings
# instead of a global "Tab = kill" escape hatch.
#
# This module is only the session. The tiles that go in it are per-host taste
# and live in that host's home.nix, next to the Firefox profile they reuse.
#
# They ride along as non-Steam shortcuts, which is the one imperative step in
# this setup — Steam owns shortcuts.vdf and rewrites it on exit, so it can't
# just be a symlinked store path. Added once through the Big Picture UI:
#   Library -> Add a Game -> Add a Non-Steam Game -> pick the couch-* wrappers
{...}: {
  flake.nixosModules."features.console" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.console;
  in {
    options.myNixOS.console = {
      enable = lib.mkEnableOption "myNixOS.console";

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Boot straight into Big Picture instead of the desktop session.

          Left off by default because a gamescope session that fails to start
          under autologin is a black screen on a TV with no way back except a
          previous-generation boot or SSH. Confirm `steam-gamescope` runs
          nested inside the desktop session first, then flip this.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      # Pulls gamescope, GE-Proton, and gamescopeSession — which is what
      # installs the `steam-gamescope` binary and registers the "steam" wayland
      # session. nixpkgs' steam module also sets hardware.steam-hardware
      # unconditionally, so the Steam Controller's udev rules come with it and
      # need no separate handling here.
      myNixOS.steam.enable = true;

      services.displayManager.defaultSession = lib.mkIf cfg.autoStart "steam";
    };
  };
}
