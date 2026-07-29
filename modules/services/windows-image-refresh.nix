# Periodically rebuild the cached Windows image so it does not rot.
#
# The image ages out via Windows Update shipping patches it does not have. A
# stale image still boots and still works — it just spends longer patching on
# first run — so this exists to keep that window short, not to gate anything.
# Deploy is deliberately NOT automated: rebuilding a cache is safe, writing to
# a physical partition is not something a timer should decide to do.
{...}: {
  flake.nixosModules."services.windows-image-refresh" = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.windows-image-refresh;
  in {
    options.myNixOS.services.windows-image-refresh = {
      enable = lib.mkEnableOption "myNixOS.services.windows-image-refresh";
      user = lib.mkOption {
        type = lib.types.str;
        description = "User to build as — needs kvm group membership; the image cache lives in its ~/.cache.";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        # Second Tuesday is Patch Tuesday, so the 15th is comfortably after it
        # while still being predictable. Off-hours and not on the hour.
        default = "*-*-15 04:17:00";
        description = "systemd OnCalendar expression for the rebuild.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.services.windows-image-refresh = {
        description = "Rebuild the cached Windows install image";
        # Needs the network for Win11Debloat and the winget app installs.
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          # A full cycle is ~11 min; the ceiling is for a cold run that has to
          # fetch an ISO from uupdump first. Bounded so a hung VM cannot sit
          # holding KVM forever.
          TimeoutStartSec = "6h";
          # Background work: never let it make the desktop stutter.
          Nice = 10;
          IOSchedulingClass = "idle";
        };
        script = ''
          ${pkgs.callPackage ../../packages/saturn-windows-image {}}/bin/saturn-windows-image \
            --build-only --rebuild
        '';
      };

      systemd.timers.windows-image-refresh = {
        description = "Monthly refresh of the cached Windows install image";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.onCalendar;
          # The machine is a desktop and is often off — without this a missed
          # window means the image silently keeps aging.
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };
    };
  };
}
