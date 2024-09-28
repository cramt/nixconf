{ pkgs, ... }:
let
  zellij_smart_start = ((import ../../scripts/zellij_smart_start.nix) {
    inherit pkgs;
  });
in
{
  programs.rio = {
    enable = true;
    settings = {
      shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = [ "-l" "-c" "${zellij_smart_start}/bin/zellij_smart_start" ];
      };
    };
  };
}
