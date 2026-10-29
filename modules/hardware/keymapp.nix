# ZSA keyboard support — udev rules only.
#
# The keymapp GUI used to ship alongside these rules and was never once
# launched; Oryx (the web flasher) only needs the rules, so the package went.
#
# Our own rules instead of `hardware.keyboard.zsa`: its Voyager line,
# `SUBSYSTEMS=="usb", ATTRS{idVendor}=="3297", MODE:="0666"`, matches every
# node under any 3297 device, and current firmware puts every ZSA board on
# 3297. So the keyboard's evdev nodes came out world-readable, and anything on
# the box could keylog it. Oryx only talks to the USB device (WebUSB flashing)
# and hidraw (WebHID live training), so only those get access, and only for
# whoever is logged in at the seat. Not reported upstream yet; the same line is
# in zsa/wally's wiki. Go back to `hardware.keyboard.zsa` once its rules stop
# matching input nodes.
{ ... }: {
  flake.nixosModules."features.keymapp" = { config, lib, pkgs, ... }: {
    options.myNixOS.keymapp.enable = lib.mkEnableOption "myNixOS.keymapp";
    config = lib.mkIf config.myNixOS.keymapp.enable {
      # Numbered below 73-seat-late, which is where logind turns uaccess into
      # ACLs; extraRules lands in 99-local, too late for that.
      services.udev.packages = [
        (pkgs.writeTextDir "lib/udev/rules.d/70-zsa.rules" ''
        # Ergodox EZ Original / Shine / Glow (Teensy)
        ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", ENV{ID_MM_DEVICE_IGNORE}="1"
        ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789A]?", ENV{MTP_NO_PROBE}="1"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789ABCD]?", TAG+="uaccess"
        KERNEL=="ttyACM*", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", TAG+="uaccess"
        # Moonlander / Planck EZ bootloader (STM32 DFU)
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess", SYMLINK+="stm32_dfu"
        # Every board on current firmware, and the Voyager bootloader
        SUBSYSTEM=="usb", ATTRS{idVendor}=="3297", TAG+="uaccess", SYMLINK+="ignition_dfu"
        KERNEL=="hidraw*", ATTRS{idVendor}=="16c0", TAG+="uaccess"
        KERNEL=="hidraw*", ATTRS{idVendor}=="3297", TAG+="uaccess"
      '')
      ];
    };
  };
}
