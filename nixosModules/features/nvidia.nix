{config, ...}: let
  driver = config.boot.kernelPackages.nvidiaPackages.stable;
in {
  config = {
    boot = {
      extraModprobeConfig = ''
        options nvidia NVreg_RestrictProfilingToAdminUsers=0 NVreg_DeviceFileMode=0666
      '';
      initrd.kernelModules = ["nvidia"];
      extraModulePackages = [driver];
    };
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
