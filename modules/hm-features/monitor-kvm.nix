# Flip the Philips 49M2C8900 between mars and saturn from a hotkey.
#
# The monitor's built-in KVM is on Auto, so the USB hub (keyboard/mouse)
# follows whichever video input is on screen: switching the input over DDC/CI
# moves the peripherals too. mars sits on USB-C (0x15), saturn on DisplayPort
# (0x0f).
#
# It toggles rather than targeting "the other host", so the same bind works
# on both machines with no per-host mapping. That relies on the monitor
# answering DDC on an input it isn't showing, which this one does.
#
# --mccs 2.2: the monitor claims MCCS 3.0, where 0x60 is a Table feature, and
# ddcutil then refuses to read/write it. Forcing 2.2 treats it as the plain
# non-continuous value it actually is.
# https://github.com/rockowitz/ddcutil/wiki/Phillips (remove if ddcutil grows a
# per-model override or Philips fixes the firmware's version claim)
{ ... }: {
  hmModules.features.monitor-kvm = { config, lib, pkgs, ... }: let
    cfg = config.myHomeManager.monitor-kvm;

    toggle = pkgs.writeShellApplication {
      name = "monitor-kvm-toggle";
      runtimeInputs = [ pkgs.ddcutil ];
      text = ''
        ddc() { ddcutil --mccs 2.2 --sn ${cfg.serial} "$@"; }

        # --terse prints e.g. "VCP 60 SNC x15"
        current=$(ddc getvcp 60 --terse | cut -d' ' -f4)
        case "$current" in
          x15) next=0x0f ;; # mars (USB-C) -> saturn (DisplayPort)
          x0f) next=0x15 ;; # saturn -> mars
          *) echo "unexpected input source '$current'" >&2; exit 1 ;;
        esac
        # Read-back right after a switch races the monitor's re-sync and fails
        # spuriously; the screen changing is the confirmation.
        ddc setvcp 60 "$next" --noverify
      '';
    };
  in {
    options.myHomeManager.monitor-kvm = {
      enable = lib.mkEnableOption "myHomeManager.monitor-kvm";
      serial = lib.mkOption {
        type = lib.types.str;
        default = "AU42447000108";
        description = "EDID serial of the shared monitor (`ddcutil detect`); its i2c bus number differs per host, the serial doesn't.";
      };
      toggle = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        description = "Script flipping the shared monitor (and its KVM) to the other host.";
      };
    };

    config = lib.mkIf cfg.enable {
      myHomeManager.monitor-kvm.toggle = lib.getExe toggle;
      home.packages = [ toggle ];
    };
  };
}
