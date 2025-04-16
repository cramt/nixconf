{pkgs, ...}: {
  config = {
    stylix.targets.vesktop = {
      enable = true;
      extraCss = ''
        :root {
            --custom-app-top-bar-height: 0;
        }
        .trailing_c38106 {
            display: none;
        }
      '';
    };
    home.packages = with pkgs; [
      vesktop
      ((import ../../scripts/kill_vesktop.nix) {
        inherit pkgs;
      })
    ];
  };
}
