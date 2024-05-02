{ lib, config, pkgs, ... }:
let
  cfg = config.myHomeManager.git;
  cmpScript = pkgs.writeShellScriptBin "git_cmp" ''
    git add -A
    git commit -m "$@"
    git push
  '';
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
    programs.gitui.enable = true;
    programs.git = {
      enable = true;
      userName = "Alexandra Østermark";
      userEmail = "alex.cramt@gmail.com";
      aliases = {
        cmp = "!${cmpScript}/bin/git_cmp";
      };
      extraConfig = {
        user = {
          signingKey = cfg.signingKey;
        };
        commit = {
          gpgsign = true;
        };
        push = {
          autoSetupRemote = true;
        };
      };
    };
  };
}
