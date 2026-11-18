# What makes a phone part of the fleet, as nixos-default.nix does for hosts:
# on the fleet tailnet (tag:fleet, like the hosts), and ssh-able with the fleet keys.
{ ... }:
let
  site = import ../../myLib/site.nix;
  keys = import ../../myLib/keys.nix;
in
{
  nixupModules.fleet = { config, lib, ... }: {
    # Userspace tailscaled next to the Android app, so the app can keep its own
    # VPN slot. Joins with the same reusable key as the hosts.
    services.tailscale = {
      enable = lib.mkDefault true;
      extraUpFlags = [ "--advertise-tags=tag:fleet" ];
      authKeyFile = config.myNixup.secrets.tailscaleNodeKey.path;
      authKeyParameters = {
        ephemeral = false;
        preauthorized = true;
      };
    };
    myNixup.secrets.tailscaleNodeKey = {
      reference = "op://Homelab/Tailscale/nodeAuthKey";
      services = [ "tailscaled-up" ];
    };

    # Sessions are root on a Nixup phone. nixup-rebuild --target-host uses this
    # too, so the phone can be rebuilt over the tailnet without adb.
    services.openssh = {
      enable = lib.mkDefault true;
      settings.PasswordAuthentication = false;
    };
    users.users.root.openssh.authorizedKeys.keys = keys.alex;
  };
}
