# NVIDIA GPU with proprietary drivers
{ ... }: {
  flake.nixosModules."features.nvidia" = { config, lib, pkgs, ... }:
  let
    driver = config.myNixOS.nvidia.package;
  in {
    options.myNixOS.nvidia = {
      enable = lib.mkEnableOption "myNixOS.nvidia";

      package = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.nvidiaPackages.stable;
        defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.stable";
        description = ''
          Driver branch to build against.

          NVIDIA moved Maxwell, Pascal and Volta to a 580 legacy branch, so
          `stable` (595.x) only covers Turing (GTX 16xx / RTX 20xx) and newer.
          On an older GPU `stable` still builds and installs cleanly and then
          fails to bind the card at runtime, which looks like a broken display
          rather than an unsupported driver — pin
          `config.boot.kernelPackages.nvidiaPackages.legacy_580` on those hosts.
        '';
      };
    };
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
