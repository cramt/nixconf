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
      lfs.enable = true;
      aliases = lib.mkMerge
        (
          [
            {
              cmp = "!${cmpScript}/bin/git_cmp";
              tswitch = "town switch";
            }
          ] ++ (
            builtins.map
              (v: { ${v} = "town ${v}"; })
              [
                "hack"
                "sync"
                "propose"
                "continue"
                "skip"
                "status"
                "undo"
                "append"
                "prepend"
                "set-parent"
                "diff-parent"
                "contribute"
                "observe"
                "park"
                "compress"
                "kill"
                "rename-branch"
                "repo"
                "ship"
              ]
          )
        );
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
    home.packages = with pkgs; [
      git-town
    ];
  };
}
