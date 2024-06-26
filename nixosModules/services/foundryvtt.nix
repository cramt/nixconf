{ pkgs, inputs, config, lib, ... }:
let
  version = "11.0.0+315";
  foundryvttPkg = inputs.foundryvtt.packages.${pkgs.system}.foundryvtt.overrideAttrs {
    version = version;
  };
  cfg = config.myNixOS.services.foundryvtt;
  dockerImage = pkgs.dockerTools.buildLayeredImage {
    name = "foundryvtt";
    tag = "11";
    contents = with pkgs; [
      cacert
      foundryvttPkg
    ];
    config = {
      Cmd = [
        "${foundryvttPkg}/bin/foundryvtt"
        "--headless"
        "--dataPath=/data"
      ];
      Env = [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
    };
  };

in
{
  options.myNixOS.services.foundryvtt = {
    dataVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the foundry data 
      '';
    };
  };
  config = {
    virtualisation.oci-containers.containers.foundryvtt = {
      hostname = "foundryvtt";
      imageFile = dockerImage;
      image = "foundryvtt:11";
      volumes = [
        "${cfg.dataVolume}:/data"
      ];
      extraOptions = [
        "--network=caddy"
        "--expose=30000"
      ];
      autoStart = true;
    };
  };
}
