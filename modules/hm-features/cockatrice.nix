{ inputs, ... }: {
  hmModules.features.cockatrice = { config, lib, pkgs, ... }: {
    options.myHomeManager.cockatrice.enable = lib.mkEnableOption "myHomeManager.cockatrice";
    config = lib.mkIf config.myHomeManager.cockatrice.enable {
      home.packages = with pkgs; [ cockatrice ];
      xdg.dataFile."Cockatrice/Cockatrice/themes/DarkMingo" = {
        enable = true;
        source = inputs.darkmingo-cockactrice-theme;
        recursive = true;
      };
    };
  };
}
