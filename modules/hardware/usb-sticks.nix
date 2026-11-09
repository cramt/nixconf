# Raw access to removable USB disks for whoever is logged in at the seat, so
# flashing and reading back installer sticks (dd, flash-installer's verify)
# needs no sudo. A slow stick outlasts sudo's credential cache mid-flash, and
# the re-prompt hides under the progress bar.
#
# Scoped to removable USB block devices only: the `disk` group would give the
# same thing for every disk, internal NVMe included, which is root in all but
# name.
{ ... }: {
  flake.nixosModules."features.usb-sticks" = { config, lib, pkgs, ... }: {
    options.myNixOS.usb-sticks.enable = lib.mkEnableOption "myNixOS.usb-sticks";
    config = lib.mkIf config.myNixOS.usb-sticks.enable {
      # Numbered below 73-seat-late, which is where logind turns uaccess into
      # ACLs; extraRules lands in 99-local, too late for that.
      services.udev.packages = [
        (pkgs.writeTextDir "lib/udev/rules.d/70-usb-sticks.rules" ''
          SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ATTRS{removable}=="1", TAG+="uaccess"
        '')
      ];
    };
  };
}
