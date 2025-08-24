{
  pkgs,
  lib,
  config,
  ...
}: let
  packages = {
    rocm = pkgs.btop-rocm;
    default = pkgs.btop;
  };
in {
  options.myHomeManager.btop = {
    hardware-accel = lib.mkOption {
      type = lib.types.enum ["rocm" "default"];
      default = "default";
      description = ''
        Type of hardware accel
      '';
    };
  };
  programs.btop = {
    enable = true;
    package = packages.${config.myHomeManager.btop.hardware-accel};
  };
}
