{ ... }: {
  hmModules.features.nautilus = { config, lib, pkgs, ... }: {
    options.myHomeManager.nautilus.enable = lib.mkEnableOption "myHomeManager.nautilus";
    config = lib.mkIf config.myHomeManager.nautilus.enable {
      xdg = {
        mimeApps = {
          enable = true;
          defaultApplications = let
            mimeTypes = [ "inode/directory" "application/x-zip" ];
          in builtins.listToAttrs (builtins.map (v: { name = v; value = "org.gnome.Nautilus.desktop"; }) mimeTypes);
        };
      };
      home.packages = with pkgs; [ nautilus ];
    };
  };
}
