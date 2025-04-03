{
  pkgs,
  lib,
  ...
}: let
  zellij_smart_start = (import ../../scripts/zellij_smart_start.nix) {
    inherit pkgs;
  };
  start = pkgs.writers.writeBash "start" ''
    ${pkgs.zsh}/bin/zsh -l -c ${zellij_smart_start}/bin/zellij_smart_start
  '';
in {
  programs.rio = {
    enable = true;
    settings = {
      confirm-before-quit = false;
      fonts = {
        size = lib.mkForce 16;
      };
      window.decorations = "Disabled";
      navigation.mode = "Plain";
      draw-bold-text-with-light-colors = true;
      hide-mouse-cursor-when-typing = true;
      shell = {
        program = start;
      };
    };
  };
}
