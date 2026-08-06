# NVIDIA GPU with proprietary drivers
{ ... }: {
  flake.nixosModules."features.nvidia" = { config, lib, ... }:
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
      # Deliberately no explicit nvidia_x11 in systemPackages or
      # graphics.extraPackages: nixpkgs' own nvidia module already adds
      # nvidia_x11.bin and the 32/64-bit GL trees derived from
      # hardware.nvidia.package.
      #
      # This used to list pkgs.linuxPackages.nvidia_x11, which is the DEFAULT
      # kernel's STABLE driver regardless of what this host actually runs. On a
      # host pinning another branch that put a second, mismatched userspace
      # tree into /run/opengl-driver — 595.84 libraries over a 580 kernel
      # module — and anything touching GL died with "Driver/library version
      # mismatch". Steam segfaulted in steamui.so on every launch.
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
