{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  boot = {
    initrd.kernelModules = ["amdgpu"];
  };

  services.xserver = {
    enable = true;
    videoDrivers = ["amdgpu"];
  };

  hardware = {
    graphics = {
      extraPackages = with pkgs; [
        rocmPackages.clr.icd
        amdvlk
      ];
      extraPackages32 = with pkgs; [
        driversi686Linux.amdvlk
      ];
      enable32Bit = true;
    };
  };
}
