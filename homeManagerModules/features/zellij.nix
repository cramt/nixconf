{ pkgs, ... }:
{
  home.packages = [
    ((import ../../scripts/zellij_smart_start.nix) {
      inherit pkgs;
    })
  ];
  programs.zellij = {
    enable = true;
    settings = {
      pane_frames = false;
    };
  };
}
