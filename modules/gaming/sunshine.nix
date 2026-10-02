# Sunshine: this host is the gaming desktop that ganymede's Moonlight streams
# games from (cramt/emrakul, "Gaming desktop" in its CONTEXT.md).
#
# It runs as nixpkgs' user service, hung off graphical-session.target, so it
# only exists while someone is logged in graphically. Getting it up with nobody
# at the desk means autologin, and getting woken by Moonlight means suspending
# instead of powering off; both change how the daily desktop behaves, so they
# are host decisions and deliberately not made here.
#
# Settings and apps are declared, which locks the web UI's config pages. The
# web UI is still where the admin login and pairing PIN go, and pairing state
# (~/.config/sunshine/sunshine_state.json + credentials/) is runtime state,
# not config.
{...}: {
  flake.nixosModules."features.sunshine" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.sunshine;
  in {
    options.myNixOS.sunshine = {
      enable = lib.mkEnableOption "myNixOS.sunshine";

      apps = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = ''
          Sunshine apps (apps.json entries) on top of the built-in "Desktop".

          Moonlight matches them by name: `moonlight stream <host> "<name>"`.
          This is where emrakul's games get declared from the same list that
          produces ganymede's desktop entries. `image-path` takes any absolute
          .png, so a store path works for box art.
        '';
      };

      wakeOnLan.interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "enp4s0";
        description = ''
          Wired interface to arm for magic-packet Wake-on-LAN. Moonlight wakes
          the host itself before `stream`/`quit`, but only from suspend: a
          powered-off board on most NICs doesn't listen.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      services.sunshine = {
        enable = true;
        openFirewall = true;
        # KMS capture reads the scanout directly, whatever the compositor. The
        # alternatives need one: wlr-screencopy is compositor-specific and the
        # portal asks for permission on screen, which nobody on the couch can
        # click. Pinned rather than auto-probed so it can't drift to those.
        capSysAdmin = true;
        settings = {
          sunshine_name = config.networking.hostName;
          capture = "kms";
        };
        applications.apps =
          [
            {
              # No cmd: streams whatever is on screen. The fallback for anything
              # not declared as its own app, and the one to pair-test against.
              name = "Desktop";
              image-path = "desktop.png";
            }
          ]
          ++ cfg.apps;
      };

      networking.interfaces = lib.mkIf (cfg.wakeOnLan.interface != null) {
        ${cfg.wakeOnLan.interface}.wakeOnLan = {
          enable = true;
          policy = ["magic"];
        };
      };
    };
  };
}
