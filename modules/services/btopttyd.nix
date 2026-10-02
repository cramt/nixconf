{ ... }: {
  flake.nixosModules."services.btopttyd" = {
    pkgs,
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.btopttyd;
    port = config.port-selector.ports.btopttyd;
  in {
    options.myNixOS.services.btopttyd = {
      enable = lib.mkEnableOption "myNixOS.services.btopttyd";
    };
    config = lib.mkIf cfg.enable {
      myNixOS.services.caddy.serviceMap.btop = {
        port = port;
        forward-auth = true;
      };

      port-selector.auto-assign = ["btopttyd"];
      services.ttyd = {
        enable = true;
        # Iosevka has to be installed on whatever machine opens the page; we
        # used to rebuild ttyd's web bundle purely to inline the font, which
        # isn't worth a yarn-hash-carrying overlay. Falls back to the browser's
        # default monospace elsewhere.
        clientOptions = {
          fontFamily = "Iosevka";
          fontSize = "16";
        };
        entrypoint = ["${pkgs.btop}/bin/btop"];
        writeable = false;
        port = port;
      };
    };
  };
}
