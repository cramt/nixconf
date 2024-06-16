{ config, ... }:
let
  colors = config.colorScheme.colors;
in
{
  services.mako = {
    enable = true;
    anchor = "bottom-right";
    width = 350;
    margin = "0,20,20";
    padding = "10";
    borderSize = 2;
    borderRadius = 5;
    defaultTimeout = 5000;
    groupBy = "summary";
    format = "<b>%s</b>\\n%b";
  };
}
