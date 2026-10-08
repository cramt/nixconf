# 1Password secrets via opnix.
#
# Every NixOS module declares the secrets it reads itself, behind its own
# enable, so a host only renders what it runs: opnix fails the whole render if
# one reference is dead, and an unused secret is just exposure. This file is the
# shared plumbing, plus the secrets home-manager reads, since an hm module can't
# declare NixOS secrets.
{ ... }: {
  flake.nixosModules."features.opnix-secrets" = { config, lib, ... }:
  let
    anyHmUser = pred: lib.any pred (lib.attrValues config.home-manager.users);
  in {
    options.myNixOS.opnix-secrets.enable = lib.mkEnableOption ''
      opnix on this host. Needs the 1Password service-account token at
      /etc/opnix-token
    '';
    config = lib.mkMerge [
      {
        # Otherwise the consumer is wired to a path nothing ever renders, and
        # only finds out at runtime.
        assertions = [
          {
            assertion = config.services.onepassword-secrets.secrets == {} || config.services.onepassword-secrets.enable;
            message = "opnix secrets declared (${lib.concatStringsSep ", " (lib.attrNames config.services.onepassword-secrets.secrets)}) but services.onepassword-secrets is off; set myNixOS.opnix-secrets.enable.";
          }
        ];
      }
      (lib.mkIf config.myNixOS.opnix-secrets.enable {
        users.users =
          builtins.mapAttrs (name: _: {
            extraGroups = ["onepassword-secrets"];
          })
          config.myNixOS.home-users;

        services.onepassword-secrets = {
          enable = true;
          tokenFile = "/etc/opnix-token";
          secrets =
            lib.optionalAttrs (anyHmUser (u: u.myHomeManager.bundles.general.enable)) {
              # Included by the user nix.conf (modules/hm-bundles/general.nix)
              # for authenticated github.com tarball fetches. Flake inputs are
              # fetched by the evaluating *client*, not the daemon, so the file
              # has to be readable by the user running nix -- as 0600 root:root
              # the `!include` was a silent no-op and every fetch took the
              # unauthenticated 60/hr rate limit.
              nixAccessTokensConf = {
                reference = "op://Homelab/GitHub/nixAccessTokensConf";
                mode = "0640";
                group = "onepassword-secrets";
              };
            }
            // lib.optionalAttrs (anyHmUser (u: u.myHomeManager.claude-code.enable || u.myHomeManager.delta.enable)) {
              cliProxyApiKey = (import ../../myLib/claude-pool.nix).apiKeySecret;
            };
        };
      })
    ];
  };
}
