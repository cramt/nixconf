# AMD GPU with ROCm support
{ ... }: {
  flake.nixosModules."features.amd" = { config, lib, pkgs, ... }: {
    options.myNixOS.amd.enable = lib.mkEnableOption "myNixOS.amd";
    config = lib.mkIf config.myNixOS.amd.enable {
      boot.initrd.kernelModules = ["amdgpu"];
      services.xserver = {
        enable = true;
        videoDrivers = ["amdgpu"];
      };
      hardware.graphics = {
        enable32Bit = true;
        extraPackages = with pkgs; [
          rocmPackages.clr.icd
        ];
      };
    };
  };
}
