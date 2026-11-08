# A node on the fleet tailnet, coordinated by myNixOS.services.headscale on luna.
#
# Joins with the shared reusable key from op://Homelab/Headscale/preauthKey,
# except on the coordinator itself, which mints its own. Mint the shared one on
# luna once with
#   sudo headscale preauthkeys create --user <fleet id> --reusable --expiration 100y
# (`sudo headscale users list` for the id). That item has to exist before any
# other host enables this: opnix fails the host's whole render on a dead
# reference.
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
    options.myNixOS.services.tailscale.enable = lib.mkEnableOption "myNixOS.services.tailscale";

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        services.tailscale = {
          enable = true;
          openFirewall = true;
          extraUpFlags = ["--login-server=${site.headscale_url}"];
        };
        # Single-owner tailnet: a node is as trusted as the LAN.
        networking.firewall.trustedInterfaces = ["tailscale0"];
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
