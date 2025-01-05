{pkgs, ...}: let
  zellij_smart_start = (import ../../scripts/zellij_smart_start.nix) {
    inherit pkgs;
  };
in {
  config = {
    stylix.targets.ghostty.enable = false;
    programs.ghostty = {
      enable = true;
      settings = {
        command = "${pkgs.zsh}/bin/zsh -l -c ${zellij_smart_start}/bin/zellij_smart_start";
        window-decoration = false;
      };
    };
  };
}
