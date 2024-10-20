{ pkgs, ... }: ((import ../../scripts/sway_gaming.nix) {
  inherit pkgs;
  direction = -100;
  output = "DP-2";
})
