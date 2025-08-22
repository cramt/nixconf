{
  pkgs,
  inputs,
  ...
}: {
  xdg.configFile."winapps/winapps.conf".source = ./winapps.conf;
  home.packages = [
    inputs.winapps.packages."${pkgs.system}".winapps
    inputs.winapps.packages."${pkgs.system}".winapps-launcher
  ];
}
