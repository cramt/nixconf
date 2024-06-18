{ ... }: {
  config = {
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
}
