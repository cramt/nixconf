# NVIDIA GPU with proprietary drivers
{ ... }: {
  flake.nixosModules."features.nvidia" = { config, lib, pkgs, ... }:
  let
    driver = config.boot.kernelPackages.nvidiaPackages.stable;
  in {
    options.myNixOS.nvidia.enable = lib.mkEnableOption "myNixOS.nvidia";
    config = lib.mkIf config.myNixOS.nvidia.enable {
      environment.systemPackages = [
        pkgs.linuxPackages.nvidia_x11
      ];
      hardware.graphics.extraPackages = [
        pkgs.linuxPackages.nvidia_x11
      ];
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
      hardware.graphics.enable = true;
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
  };
}
