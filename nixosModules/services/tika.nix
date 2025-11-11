{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  port = config.port-selector.ports.tika;
in {
  config = {
    port-selector.auto-assign = ["tika"];
    services.tika = {
      inherit port;
      enable = true;
    };
  };
}
