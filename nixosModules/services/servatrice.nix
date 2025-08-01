{
  pkgs,
  lib,
  config,
  ...
}: let
  servatricePkg = pkgs.cockatrice.overrideAttrs (final: prev: {
    pname = "servatrice";
    cmakeFlags = ["-DWITH_SERVER=1" "-DWITH_CLIENT=0" "-DWITH_ORACLE=0" "-DWITH_DBCONVERTER=0"];
  });
  starter = pkgs.writeShellScriptBin "servatrice_starter" ''
    ${servatricePkg}/bin/servatrice --config /config/servatrice.ini --log-to-console
  '';
  dockerImage = pkgs.dockerTools.streamLayeredImage {
    name = "servatrice";
    tag = "1";
    contents = with pkgs; [
      coreutils
      envsubst
      cacert
      servatricePkg
      starter
    ];
    config = {
      Cmd = [
        "${starter}/bin/servatrice_starter"
      ];
      Env = ["SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];
    };
  };

  configFile = pkgs.writeText "servatrice.ini" (lib.generators.toINI {} {
    server = {
      name = "Luna Cockatrice Server";
      id = 1;
      host = "any";
      port = 4747;
      number_pools = 1;
      websocket_host = "any";
      websocket_port = 4748;
      websocket_number_pools = 1;
      statusupdate = 15000;
      writelog = 1;
      logfile = "/var/logs/Servatrice/servatrice.log";
      logfilters = "";
      clientkeepalive = 1;
      max_player_inactivity_time = 15;
      requireclientid = false;
      requiredfeatures = "";
      officialwarnings = "Flamming,Spamming,Causing Drama,Abusive Language";
      idleclienttimeout = 3600;
    };
    authentication = {
      method = "password";
      password = (import ../../secrets.nix).cockatrice_password;
      regonly = true;
    };
    database = {
      type = "none";
    };
    rooms = {
      method = "config";
      "roomList\\size" = 1;
      "roomList\\1\\name" = "General Room";
      "roomList\\1\\description" = "General Room";
    };
  });
in {
  config = {
    virtualisation.oci-containers.containers.servatrice = {
      hostname = "servatrice";
      imageStream = dockerImage;
      image = "servatrice:1";
      volumes = [
        "${configFile}:/config/servatrice.ini"
      ];
      ports = [
        "4747:4747"
        "4748:4748"
      ];
      autoStart = true;
    };
  };
}
