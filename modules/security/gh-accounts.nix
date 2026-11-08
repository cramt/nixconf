# `gh` logins for a headless user, from 1Password instead of `gh auth login`.
#
# With no keyring on a headless box gh keeps tokens in plaintext in
# ~/.config/gh/hosts.yml, so that file is rendered from 1Password rather than left
# as hand-made state that's lost with the disk. gh supports several accounts
# per host there; `active` is the one plain `gh` uses, and the others are
# reachable with `gh auth switch`, `gh auth token --user <login>`, or by
# pinning them in T3 Code's Settings → Source Control.
#
# gh rewrites the file on `gh auth switch`, so it is a real file, not a store
# symlink. The render reruns with op-secrets, so a switch lasts until the next
# deploy that touches this or the next boot, then `active` wins again.
{ ... }: {
  flake.nixosModules."features.gh-accounts" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.gh-accounts;
    capitalize = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s;
    secretName = login:
      "ghToken" + lib.concatMapStrings capitalize (lib.filter (p: p != "") (lib.splitString "-" login));
    tokenPath = login: config.myNixOS.secrets.${secretName login}.path;
    accounts = {${cfg.active.login} = cfg.active.tokenReference;} // cfg.others;
    hostsYml = "/home/${cfg.user}/.config/gh/hosts.yml";
    render = pkgs.writeShellApplication {
      name = "gh-accounts-render";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        tok() { tr -d '[:space:]' < "$1"; }
        dir=$(dirname ${hostsYml})
        install -d -m700 -o ${cfg.user} -g ${config.users.users.${cfg.user}.group} "$dir"
        umask 077
        {
          echo '${cfg.host}:'
          echo '    users:'
          ${lib.concatMapStrings (login: ''
            echo '        ${login}:'
            echo "            oauth_token: $(tok ${tokenPath login})"
          '') (lib.attrNames accounts)}
          echo '    git_protocol: ${cfg.gitProtocol}'
          echo '    user: ${cfg.active.login}'
          echo "    oauth_token: $(tok ${tokenPath cfg.active.login})"
        } > "$dir/hosts.yml.new"
        chown ${cfg.user}:${config.users.users.${cfg.user}.group} "$dir/hosts.yml.new"
        mv "$dir/hosts.yml.new" ${hostsYml}
      '';
    };
  in {
    options.myNixOS.gh-accounts = {
      enable = lib.mkEnableOption "myNixOS.gh-accounts";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = "Login user whose ~/.config/gh/hosts.yml is rendered.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "github.com";
      };
      gitProtocol = lib.mkOption {
        type = lib.types.enum ["ssh" "https"];
        default = "ssh";
      };
      # Split into active + others rather than a list plus an "active" name, so
      # an active account that isn't among the logins can't be written down.
      active = {
        login = lib.mkOption {type = lib.types.str;};
        tokenReference = lib.mkOption {
          type = lib.types.str;
          example = "op://Homelab/GitHub/someToken";
        };
      };
      others = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        example = {cramt = "op://Homelab/GitHub/cramtToken";};
        description = "Further logins on the same host, login → 1Password reference.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !(cfg.others ? ${cfg.active.login});
          message = "myNixOS.gh-accounts: ${cfg.active.login} is both active and in others.";
        }
      ];

      myNixOS.secrets = lib.mapAttrs' (login: reference:
        lib.nameValuePair (secretName login) {
          inherit reference;
          mode = "0600";
        })
      accounts;

      systemd.services.gh-accounts = {
        description = "Render ${cfg.user}'s gh logins from 1Password";
        wantedBy = ["multi-user.target"];
        # partOf: when op-secrets restarts after a token is rotated in 1Password,
        # the file is rendered again from the fresh secrets.
        after = ["op-secrets.service"];
        requires = ["op-secrets.service"];
        partOf = ["op-secrets.service"];
        restartTriggers = [render];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe render;
        };
      };
    };
  };
}
