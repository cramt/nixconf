{ ... }: {
  hmModules.features.git = { config, lib, pkgs, ... }: let
    cfg = config.myHomeManager.git;
    cmpScript = pkgs.writeShellScriptBin "git_cmp" ''
      git add -A
      git commit -m "$@"
      git push
    '';
  in {
    options.myHomeManager.git = {
      enable = lib.mkEnableOption "myHomeManager.git";
      signingKey = lib.mkOption {
        default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I";
        description = "the ssh signing key (public key)";
      };
      use1Password = lib.mkOption {
        type = lib.types.bool;
        # Follows the ssh feature: a host that already declared it has no
        # 1Password shouldn't then get op-ssh-sign as its commit signer — that
        # both fails at runtime and drags the whole 1Password GUI into the
        # closure of machines with no GUI at all. `or true` keeps this working
        # if the ssh feature isn't imported.
        default = config.myHomeManager.ssh.use1Password or true;
        defaultText = "config.myHomeManager.ssh.use1Password";
        description = ''
          Whether to sign commits through 1Password's op-ssh-sign. When false,
          uses the stock ssh-keygen signer, which keeps signed commits working
          over plain SSH keys.
        '';
      };
    };
    config = lib.mkIf cfg.enable {
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
                  "delete" "rename" "hack" "sync" "propose" "continue" "skip"
                  "status" "undo" "append" "prepend" "set-parent" "diff-parent"
                  "contribute" "observe" "park" "compress" "repo" "ship"
                ]
              )
            );
          gpg = {
            format = "ssh";
            ssh.program =
              if cfg.use1Password
              then "${lib.getExe' pkgs._1password-gui "op-ssh-sign"}"
              else "${lib.getExe' pkgs.openssh "ssh-keygen"}";
          };
          commit = { gpgsign = true; };
          push = { autoSetupRemote = true; };
          pull = { rebase = true; };
          rebase = { updateRefs = true; };
        };
      };
      home.packages = with pkgs; [ git-town git-crypt ];
    };
  };
}
