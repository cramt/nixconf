{pkgs, ...}: let
  zellij_smart_start = (import ../../scripts/zellij_smart_start.nix) {
    inherit pkgs;
  };
in {
  config = {
    stylix.targets.ghostty.enable = true;
    programs.ghostty = {
      enable = true;
      settings = {
        command = "${pkgs.zsh}/bin/zsh -l -c ${zellij_smart_start}/bin/zellij_smart_start";
        window-decoration = false;
        window-padding-x = 0;
        window-padding-y = 0;
      };
    };
  };
}
