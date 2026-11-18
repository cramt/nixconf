# A node on the fleet tailnet, on Tailscale's own control server. The tailnet
# itself (ACL, DNS, HTTPS) is infra/tailscale.nix.
#
# On by default on every host. Joins with op://Homelab/Tailscale/nodeAuthKey,
# an OAuth client secret scoped to auth_keys and tag:fleet: unlike an auth
# key it never expires, and tagged nodes get no key expiry either. It was
# minted through the API (POST /api/v2/tailnet/-/keys, keyType "client"),
# because a terraform-made one couldn't reach 1Password.
{ ... }: {
  flake.nixosModules."services.tailscale" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.tailscale;
    controlUrl = "https://controlplane.tailscale.com";
    tags = "--advertise-tags=tag:fleet";
  in {
    options.myNixOS.services.tailscale.enable = lib.mkEnableOption "myNixOS.services.tailscale" // {default = true;};

    config = lib.mkIf cfg.enable {
      myNixOS.secrets.tailscaleNodeKey = {
        reference = "op://Homelab/Tailscale/nodeAuthKey";
        services = ["tailscaled-autoconnect"];
      };

      services.tailscale = {
        enable = true;
        openFirewall = true;
        authKeyFile = config.myNixOS.secrets.tailscaleNodeKey.path;
        authKeyParameters = {
          ephemeral = false;
          preauthorized = true;
        };
        extraUpFlags = [tags];
      };
      # Single-owner tailnet: a node is as trusted as the LAN. Nodes shared in
      # from another tailnet can't open connections to ours, only answer.
      networking.firewall.trustedInterfaces = ["tailscale0"];
      # A join that fails (control server or DNS not up yet) would otherwise
      # wait for the next deploy or reboot.
      systemd.services.tailscaled-autoconnect.serviceConfig = {
        Restart = "on-failure";
        RestartSec = 30;
      };
      systemd.services.tailscaled-autoconnect.unitConfig.StartLimitIntervalSec = 0;
      # tailscaled keeps the control server from its last login in its state,
      # and extraUpFlags only reaches it when autoconnect sees NeedsLogin. A
      # node last logged in elsewhere (luna's old headscale, or before that
      # hs.re-zip.com) sits retrying it, and autoconnect waits forever. Rejoin
      # here when the saved server isn't ours. `debug prefs` is the only CLI
      # that prints ControlURL.
      systemd.services.tailscaled-autoconnect.preStart = ''
        url="$(tailscale debug prefs | jq -r .ControlURL)"
        if [ "$url" != "${controlUrl}" ]; then
          echo "control server is $url, not ${controlUrl}: rejoining"
          tailscale up --reset --force-reauth ${tags} \
            --auth-key "$(cat ${config.services.tailscale.authKeyFile})?ephemeral=false&preauthorized=true" \
            --login-server=${controlUrl}
        fi
      '';
    };
  };
}
