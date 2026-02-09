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
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I";
      description = ''
        the ssh signing key (public key)
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
          backend = "ssh";
          key = cfg.signingKey;
          backends.ssh.program = "${lib.getExe' pkgs._1password-gui "op-ssh-sign"}";
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
