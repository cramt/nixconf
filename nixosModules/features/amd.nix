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
      ];
    };
  };
}
