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
      enable32Bit = true;
      extraPackages = with pkgs; [
        rocmPackages.clr.icd
      ];
    };
  };
}
