{ ... }: {
  hmModules.features.zathura = { config, lib, pkgs, ... }: {
    options.myHomeManager.zathura.enable = lib.mkEnableOption "myHomeManager.zathura";
    config = lib.mkIf config.myHomeManager.zathura.enable {
      xdg = {
        mimeApps = {
          enable = true;
          defaultApplications =
            let
              mimeTypes = [
                "application/pdf"
              ];
            in
            builtins.listToAttrs (builtins.map (v: { name = v; value = "org.pwmt.zathura.desktop"; }) mimeTypes);
        };
      };
      programs.zathura = {
        enable = true;
        options = {
          selection-clipboard = "clipboard";
        };
      };
    };
  };
}
