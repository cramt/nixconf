{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myHomeManager.jujutsu;
in {
  options.myHomeManager.jujutsu = {
    signingKey = lib.mkOption {
      default = "";
      description = ''
        the gpg signing key
      '';
    };
  };
  config = {
    programs.jujutsu = {
      enable = true;
      settings = {
        user = {
          email = "alex.cramt@gmail.com";
          name = "Alexandra Østermark";
        };
        signing = {
          sign-all = true;
          backend = "gpg";
          key = cfg.signingKey;
        };
        aliases = {
          push_new = ["git" "push" "-c" "@"];
          push_main = ["git" "push"];
          fetch = ["git fetch"];
        };
      };
    };
  };
}
