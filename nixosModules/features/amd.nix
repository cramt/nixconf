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

  hardware.opengl = {
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
      amdvlk
    ];
    driSupport = true; # 
    driSupport32Bit = true;
    extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
    ];

  };
}
