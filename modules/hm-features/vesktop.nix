{ ... }: {
  hmModules.features.vesktop = { config, lib, pkgs, ... }: {
    options.myHomeManager.vesktop.enable = lib.mkEnableOption "myHomeManager.vesktop";
    config = lib.mkIf config.myHomeManager.vesktop.enable {
      programs.vesktop = {
        enable = true;
        vencord.themes.stylix = lib.mkAfter ''
          :root { --custom-app-top-bar-height: 0; }
          .trailing_c38106 { display: none; }
        '';
      };
      home.packages = with pkgs; [
        ((import ../../scripts/kill_vesktop.nix) { inherit pkgs; })
      ];
    };
  };
}
