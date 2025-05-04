{config, ...}: let
  colors = config.colorScheme.colors;
in {
  services.mako = {
    enable = true;
    settings = {
      anchor = "bottom-right";
      margin = "0,20,20";
      padding = "10";
      groupBy = "summary";
      format = "<b>%s</b>\\n%b";
    };
  };
}
