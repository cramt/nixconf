{
  pkgs,
  lib,
  config,
  ...
}: let
  # Wrap a btop package so it can find NVML (libnvidia-ml.so.1) at runtime. [1](https://deepwiki.com/aristocratos/btop/2.1.5-gpu-collection)[2](https://www.reddit.com/r/NixOS/comments/18v6swm/what_package_provides_libnvidiamlso/)
  mkNvmlWrappedBtop = btopPkg:
    pkgs.symlinkJoin {
      name = "${(btopPkg.pname or "btop")}-nvml";
      paths = [btopPkg];
      buildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram "$out/bin/btop" \
          --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib
      '';
    };

  packages = {
    rocm = pkgs.btop-rocm;
    default = mkNvmlWrappedBtop pkgs.btop; # <- your NVIDIA/NVML-safe default
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
