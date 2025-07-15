{pkgs, ...}: let
  secrets = import ../../secrets.nix;
  authKeyFile = pkgs.writeText "tailscale-auth-key" secrets.tailscale_preauth_key;
in {
  services.tailscale = {
    enable = true;
    authKeyFile = authKeyFile;
    authKeyParameters = {
      preauthorized = true;
      baseURL = secrets.tailscale_base_url;
    };
  };
}
