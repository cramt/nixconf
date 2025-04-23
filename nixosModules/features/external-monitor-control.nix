{
  pkgs,
  config,
  ...
}: {
  hardware.i2c.enable = false;
  boot = {
    extraModulePackages = [
      config.boot.kernelPackages.ddcci-driver
    ];
    kernelModules = [
      "i2c_dev"
    ];
  };
  services.udev = {
    packages = [pkgs.ddcutil];
    extraRules = ''
      ACTION=="add", SUBSYSTEM=="i2c", TAG+="ddcci", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ddcci@$kernel.service"
    '';
  };
  environment.systemPackages = [pkgs.ddcutil];
  services.ddccontrol.enable = true;
  systemd.services."ddcci@" = {
    scriptArgs = "%i";
    script = ''
      echo Trying to attach ddcci to $1
      id=$(echo $1 | cut -d "-" -f 2)
      if ${pkgs.ddcutil}/bin/ddcutil getvcp 10 -b $id; then
        echo ddcci 0x37 > /sys/bus/i2c/devices/$1/new_device
      fi
    '';
    serviceConfig.Type = "oneshot";
  };
}
