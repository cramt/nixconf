{ config, pkgs, lib, ... }:
{
  boot = {
    initrd.kernelModules = [ "amdgpu" ];
    kernelParams = [ "radeon.si_support=0" "amdgpu.si_support=1" ];
  };


  services.xserver = {
    enable = true;
    videoDrivers = [ "amdgpu" ];
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
