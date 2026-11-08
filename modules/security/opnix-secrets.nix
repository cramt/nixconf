# 1Password secrets via opnix, on every host: each one carries the
# service-account token at /etc/opnix-token (the flash-* images bake it in).
#
# Every NixOS module declares the secrets it reads itself, behind its own
# enable, so a host only renders what it runs: opnix fails the whole render if
# one reference is dead, and an unused secret is just exposure. This file is the
# shared plumbing, plus the secrets home-manager reads, since an hm module can't
# declare NixOS secrets.
{...}: {
  flake.nixosModules."features.opnix-secrets" = {
    config,
    lib,
    ...
  }: let
    anyHmUser = pred: lib.any pred (lib.attrValues config.home-manager.users);
    # Hosts like mercury import only a subset of the hm features, and eros none
    # of them, so the option can be absent, which can only mean off.
    hmEnabled = path: u: lib.attrByPath (["myHomeManager"] ++ path ++ ["enable"]) false u;
  in {
    config = {
      users.users =
        builtins.mapAttrs (name: _: {
          extraGroups = ["onepassword-secrets"];
        })
        config.myNixOS.home-users;

      services.onepassword-secrets = {
        enable = true;
        tokenFile = "/etc/opnix-token";
        secrets =
          lib.optionalAttrs (anyHmUser (hmEnabled ["bundles" "general"])) {
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
          // lib.optionalAttrs (lib.any (p: anyHmUser (hmEnabled [p])) ["claude-code" "delta"]) {
            cliProxyApiKey = (import ../../myLib/claude-pool.nix).apiKeySecret;
          };
      };
    };
  };
}
