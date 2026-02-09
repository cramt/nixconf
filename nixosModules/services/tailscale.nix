{config, ...}: let
  site = import ../../site.nix;
in {
  services.tailscale = {
    enable = true;
    authKeyFile = config.services.onepassword-secrets.secretPaths.tailscalePreauthKey;
    authKeyParameters = {
      preauthorized = true;
      baseURL = site.tailscale_base_url;
    };
  };
}
