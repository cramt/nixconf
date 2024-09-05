{ pkgs, ... }: {
  config = {
    stylix.targets.vesktop.enable = true;
    home.packages = with pkgs; [
      vesktop
      ((import ../../scripts/kill_vesktop.nix) {
        inherit pkgs;
      })
    ];
  };
}
