{config, ...}: let
  secrets = import ../../secrets.nix;
in {
  services.tailscale = {
    enable = true;
    authKeyFile = config.services.onepassword-secrets.secretPaths.tailscalePreauthKey;
    authKeyParameters = {
      preauthorized = true;
      baseURL = secrets.tailscale_base_url;
    };
  };
}
