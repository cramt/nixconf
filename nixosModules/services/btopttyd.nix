{pkgs, ...}: let
  port = 7681;
in {
  options = {};
  config = {
    myNixOS.services.caddy.serviceMap = {
      btop = {
        port = port;
        basic-auth = {
          username = "admin";
          hashed-password = "$2a$14$3elBL1TrHKl9Ei10/PqFfudA8v939SirZN1sAynDbsWOE5t.eT3AK";
        };
      };
    };
    services.ttyd = {
      enable = true;
      clientOptions = {
        fontFamily = "Iosevka";
        fontSize = "16";
      };
      entrypoint = ["${pkgs.btop}/bin/btop"];
      writeable = false;
      port = port;
    };
  };
}
