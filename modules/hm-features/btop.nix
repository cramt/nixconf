{ ... }: {
  hmModules.features.btop = { config, lib, pkgs, ... }: let
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
      default = mkNvmlWrappedBtop pkgs.btop;
    };
  in {
    options.myHomeManager.btop = {
      enable = lib.mkEnableOption "myHomeManager.btop";
      hardware-accel = lib.mkOption {
        type = lib.types.enum ["rocm" "default"];
        default = "default";
        description = "Type of hardware accel";
      };
    };
    config = lib.mkIf config.myHomeManager.btop.enable {
      programs.btop = {
        enable = true;
        package = packages.${config.myHomeManager.btop.hardware-accel};
      };
    };
  };
}
