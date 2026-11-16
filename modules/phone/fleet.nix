# What makes a phone part of the fleet, as nixos-default.nix does for hosts:
# on the tailnet through luna's headscale, and ssh-able with the fleet keys.
{ ... }:
let
  site = import ../../myLib/site.nix;
  keys = import ../../myLib/keys.nix;
in
{
  nixupModules.fleet = { lib, ... }: {
    # Userspace tailscaled next to the Android app, so the app can keep its own
    # VPN slot. No authKeyFile: Nixup only reads secrets from a file next to the
    # config or one already on the phone, and a flake puts the former in the
    # world-readable store. The first build prints a registration link instead;
    # approve it on luna with `headscale nodes register`.
    services.tailscale = {
      enable = lib.mkDefault true;
      extraUpFlags = [ "--login-server=${site.headscale_url}" ];
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
