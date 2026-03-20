{pkgs, ...}: {
  home.packages = [
    (pkgs.callPackage ../../packages/t3code/default.nix {})
  ];
}
