{pkgs, ...}: {
  programs.btop = {
    enable = true;
    package = pkgs.btop.overrideAttrs (oldAttrs: {
      rocmSupport = true;
      cudaSupport = true;
    });
  };
}
