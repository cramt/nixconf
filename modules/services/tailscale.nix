# A node on the fleet tailnet, coordinated by myNixOS.services.headscale on luna.
#
# On by default on every host. Joins with the shared reusable key in
# op://Homelab/Headscale/preauthKey, except on the coordinator itself, which
# mints its own. To re-mint the shared one, from a host with `op`:
#   id=$(ssh root@luna headscale users list -o json | jq -r '.[] | select(.name=="fleet") | .id')
#   ssh root@luna headscale preauthkeys create --reusable --expiration 87600h --user "$id"
{ ... }: {
  flake.nixosModules."services.tailscale" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.tailscale;
    coordinator = config.myNixOS.services.headscale;
    site = import ../../myLib/site.nix;
  in {
    options.myNixOS.services.tailscale.enable = lib.mkEnableOption "myNixOS.services.tailscale" // {default = true;};

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        services.tailscale = {
          enable = true;
          openFirewall = true;
          extraUpFlags = ["--login-server=${site.headscale_url}"];
        };
        # Single-owner tailnet: a node is as trusted as the LAN.
        networking.firewall.trustedInterfaces = ["tailscale0"];
        # A join that fails (headscale or DNS not up yet) would otherwise wait
        # for the next deploy or reboot.
        systemd.services.tailscaled-autoconnect.serviceConfig = {
          Restart = "on-failure";
          RestartSec = 30;
        };
        systemd.services.tailscaled-autoconnect.unitConfig.StartLimitIntervalSec = 0;
      }
      (lib.mkIf coordinator.enable {
        services.tailscale.authKeyFile = coordinator.localKeyFile;
        systemd.services.tailscaled-autoconnect = {
          after = ["headscale-local-key.service"];
          requires = ["headscale-local-key.service"];
        };
      })
      (lib.mkIf (!coordinator.enable) {
        services.onepassword-secrets.secrets.headscalePreauthKey = {
          reference = "op://Homelab/Headscale/preauthKey";
          services = ["tailscaled-autoconnect"];
        };
        services.tailscale.authKeyFile = config.services.onepassword-secrets.secretPaths.headscalePreauthKey;
      })
    ]);
  };
}
