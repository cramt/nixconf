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
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.console;
  in {
    options.myNixOS.console = {
      enable = lib.mkEnableOption "myNixOS.console";

      mode = lib.mkOption {
        type = lib.types.enum ["gamescope" "bigpicture"];
        default = "gamescope";
        description = ''
          How the couch UI gets on screen.

          "gamescope" makes Steam's gamescope session the entire shell. Better
          when it works — per-game render resolution, FSR upscaling, HDR — but
          gamescope ties its DRM (scanout) device to its Vulkan (compositing)
          device and offers no way to separate them. So it only works where the
          GPU it can composite on is also the one the screen hangs off.

          "bigpicture" leaves the desktop session in charge and auto-starts
          Steam in Big Picture inside it. The desktop compositor handles output,
          which means multi-GPU works properly, at the cost of gamescope's
          scaling. Use this on hybrid graphics where the display is attached to
          a GPU gamescope can't composite on.
        '';
      };

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

      output = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "HDMI-A-1";
        description = ''
          Connector to prefer, passed to gamescope as --prefer-output.

          Worth setting on any laptop: the internal panel is still connected
          with the lid shut, so gamescope is free to pick it over the TV and
          leave the screen you can actually see blank.
        '';
      };

      vkDevice = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "10de:1c8c";
        description = ''
          PCI vendor:device of the GPU to composite on, passed to gamescope as
          --prefer-vk-device.

          Needed on hybrid graphics, where gamescope may otherwise composite on
          the integrated GPU while the TV hangs off the discrete one.
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

      programs.steam.gamescopeSession.args =
        lib.optionals (cfg.output != null) ["--prefer-output" cfg.output]
        ++ lib.optionals (cfg.vkDevice != null) ["--prefer-vk-device" cfg.vkDevice];

      services.displayManager.defaultSession =
        lib.mkIf (cfg.autoStart && cfg.mode == "gamescope") "steam";

      # In gamescope mode the session itself is Steam, so steam_background is
      # redundant by definition and a second launch would at best exit as a
      # duplicate. In bigpicture mode it's the opposite: that service IS how
      # the couch UI gets started, so point it at Big Picture rather than the
      # silent tray client.
      systemd.user.services.steam_background = lib.mkMerge [
        {enable = lib.mkForce (cfg.mode == "bigpicture" || !cfg.autoStart);}
        (lib.mkIf (cfg.mode == "bigpicture" && cfg.autoStart) {
          serviceConfig.ExecStart =
            lib.mkForce "${pkgs.steam}/bin/steam -tenfoot";
        })
      ];
    };
  };
}
