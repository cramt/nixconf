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
      session_serialization = false;
      pane_viewport_serialization = false;
    };
  };
}
