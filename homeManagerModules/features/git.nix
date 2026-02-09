{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.myHomeManager.git;
  cmpScript = pkgs.writeShellScriptBin "git_cmp" ''
    git add -A
    git commit -m "$@"
    git push
  '';
in {
  options.myHomeManager.git = {
    signingKey = lib.mkOption {
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I";
      description = ''
        the ssh signing key (public key)
      '';
    };
  };
  config = {
    programs.gitui = {
      enable = true;
      keyConfig = ''
        (
            exit_popup: Some(( code: Char('q'), modifiers: "")),
            quit: Some(( code: Char('Q'), modifiers: "SHIFT")),
            commit: Some(( code: Char('S'), modifiers: "SHIFT")),
        )
      '';
    };
    programs.git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "Alexandra Østermark";
          email = "alex.cramt@gmail.com";
          signingKey = cfg.signingKey;
        };
        alias =
          lib.mkMerge
          (
            [
              {
                cmp = "!${cmpScript}/bin/git_cmp";
                tswitch = "town switch";
              }
            ]
            ++ (
              builtins.map
              (v: {${v} = "town ${v}";})
              [
                "delete"
                "rename"
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
                "repo"
                "ship"
              ]
            )
          );
        gpg = {
          format = "ssh";
          ssh.program = "${lib.getExe' pkgs._1password-gui "op-ssh-sign"}";
        };
        commit = {
          gpgsign = true;
        };
        push = {
          autoSetupRemote = true;
        };
        pull = {
          rebase = true;
        };
        rebase = {
          updateRefs = true;
        };
      };
    };
    home.packages = with pkgs; [
      git-town
      git-crypt
    ];
  };
}
