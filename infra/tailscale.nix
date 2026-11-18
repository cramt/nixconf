# The fleet tailnet (tailaf2719.ts.net) on Tailscale's control server. Nodes
# join through modules/services/tailscale.nix.
#
# The provider authenticates with op://Homelab/Tailscale/oauthClient{Id,Secret}
# (scopes policy_file, dns, feature_settings, devices:core:read); the wrapper in
# modules/flake/infra.nix exports them. Both OAuth clients were minted through
# the API rather than here: a secret terraform creates would only land in
# state, and hosts read theirs from 1Password.
{ ... }:
let
  fleetTag = "tag:fleet";
in
{
  resource.tailscale_acl.fleet = {
    # Adopts whatever the admin console holds; this file is the only source.
    overwrite_existing_content = true;
    acl = builtins.toJSON {
      # nodeAuthKey's OAuth client can only mint keys for tags listed here.
      tagOwners.${fleetTag} = [ "autogroup:admin" ];
      # Single owner: every node reaches every node, like the LAN.
      grants = [{ src = [ "*" ]; dst = [ "*" ]; ip = [ "*" ]; }];
    };
  };

  resource.tailscale_dns_preferences.fleet.magic_dns = true;

  resource.tailscale_tailnet_settings.fleet = {
    # Certs for <host>.tailaf2719.ts.net (myNixOS.tailnet-https).
    https_enabled = true;
    devices_approval_on = false;
    # Nodes are NixOS: tailscale updates come with nixpkgs, never by itself.
    devices_auto_updates_on = false;
  };
}
