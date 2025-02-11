{pkgs, ...}: {
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        authorColors = {
          "Alexandra Østermark" = "#b00b69";
        };
      };
    };
  };
}
