{ pkgs, ... }: {
  qt = {
    enable = true;
    platformTheme = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };
}
