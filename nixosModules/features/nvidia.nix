{config, ...}: let
  driver = config.boot.kernelPackages.nvidiaPackages.stable;
in {
  config = {
    boot.initrd.kernelModules = ["nvidia"];
    boot.extraModulePackages = [driver];
    services.xserver = {
      enable = true;
      videoDrivers = ["nvidia"];
    };
    hardware.graphics = {
      enable = true;
    };
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement = {
        enable = false;
        finegrained = false;
      };
      open = false;
      nvidiaSettings = true;
      package = driver;
    };
  };
}
