{ config, pkgs, lib, ... }:
let
  cfg = config.myNixOS.nvidia;
in
{
  options.myNixOS.nvidia = {
    prime = lib.mkOption {
      default = { };
      description = ''
        the gpg signing key
      '';
    };
    package_version = lib.mkOption {
      default = "stable";
      description = ''
        the package version to use
      '';
    };
  };
  config = {
    boot = {
      initrd.kernelModules = [ "nvidia" ];
      kernelParams = [ "nvidia_drm.fbdev=1" "nvidia_drm.modeset=1" ];
      blacklistedKernelModules = [ "nouveau" ];
    };
    environment.sessionVariables = {
      WLR_RENDERER = "vulkan";
      WLR_NO_HARDWARE_CURSORS = "1";
      XWAYLAND_NO_GLAMOR = "1";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      LIBVA_DRIVER_NAME = "nvidia";
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
      DRI_PRIME = "1";
    };
    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [
        vulkan-validation-layers
        rocm-opencl-icd
        rocm-opencl-runtime
        vaapiVdpau
      ];
    };

    nixpkgs.config.nvidia.acceptLicense = true;

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {

      # Modesetting is required.
      modesetting.enable = true;

      # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
      # Enable this if you have graphical corruption issues or application crashes after waking
      # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
      # of just the bare essentials.
      powerManagement.enable = false;

      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or newer).
      powerManagement.finegrained = false;

      # Use the NVidia open source kernel module (not to be confused with the
      # independent third-party "nouveau" open source driver).
      # Support is limited to the Turing and later architectures. Full list of 
      # supported GPUs is at: 
      # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
      # Only available from driver 515.43.04+
      # Currently alpha-quality/buggy, so false is currently the recommended setting.
      open = false;

      # Enable the Nvidia settings menu,
      # accessible via `nvidia-settings`.
      nvidiaSettings = true;

      # Optionally, you may need to select the appropriate driver version for your specific GPU.
      # https://nixos.wiki/wiki/Nvidia#Running_the_new_RTX_SUPER_on_nixos_stable
      package =
        if cfg.package_version == "patch" then
          let
            rcu_patch = pkgs.fetchpatch {
              url = "https://github.com/gentoo/gentoo/raw/c64caf53/x11-drivers/nvidia-drivers/files/nvidia-drivers-470.223.02-gpl-pfn_valid.patch";
              hash = "sha256-eZiQQp2S/asE7MfGvfe6dA/kdCvek9SYa/FFGp24dVg=";
            };
          in
          config.boot.kernelPackages.nvidiaPackages.mkDriver {
            version = "535.154.05";
            sha256_64bit = "sha256-fpUGXKprgt6SYRDxSCemGXLrEsIA6GOinp+0eGbqqJg=";
            sha256_aarch64 = "sha256-G0/GiObf/BZMkzzET8HQjdIcvCSqB1uhsinro2HLK9k=";
            openSha256 = "sha256-wvRdHguGLxS0mR06P5Qi++pDJBCF8pJ8hr4T8O6TJIo=";
            settingsSha256 = "sha256-9wqoDEWY4I7weWW05F4igj1Gj9wjHsREFMztfEmqm10=";
            persistencedSha256 = "sha256-d0Q3Lk80JqkS1B54Mahu2yY/WocOqFFbZVBh+ToGhaE=";

            patches = [ rcu_patch ];
          }
        else config.boot.kernelPackages.nvidiaPackages.${cfg.package_version};
      prime = cfg.prime;
    };
  };
}
