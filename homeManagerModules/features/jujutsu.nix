{
  lib,
  config,
  pkgs,
  inputs,
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
        git = {
          auto-locale-bookmark = true;
        };
        aliases = {
          push_new = ["git" "push" "-c" "@"];
          push_curr = ["git" "push"];
          fetch = ["git" "fetch"];
          clone = ["git" "clone"];
          sync = ["rebase -d" "main"];
        };
      };
    };
  };
}
