{ lib, config, ... }:
let
  cfg = config.myHomeManager.git;
in
{
  options.myHomeManager.git = {
    signingKey = lib.mkOption {
      default = "";
      description = ''
        the gpg signing key
      '';
    };
  };
  config = {
    programs.git = {
      enable = true;
      userName = "Alexandra Østermark";
      userEmail = "alex.cramt@gmail.com";
      extraConfig = {
        user = {
          signingKey = cfg.signingKey;
        };
        commit = {
          gpgsign = true;
        };
      };
    };
  };
}
