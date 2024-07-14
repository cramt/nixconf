{ pkgs, ... }: {
  config = {
    xdg = {
      mimeApps = {
        enable = true;
        defaultApplications =
          let
            mimeTypes = [
              "inode/directory"
              "application/x-zip"
            ];
          in
          builtins.listToAttrs (builtins.map (v: { name = v; value = "org.gnome.Nautilus.desktop"; }) mimeTypes);
      };
    };
    home.packages = with pkgs; [
      nautilus
    ];
  };
}
