# cramt's own Claude subscription pool: the cli-proxy-api on luna
# (modules/services/cli-proxy-api.nix), shared by every host's `claude` wrapper
# (modules/hm-features/claude-code.nix) and Zed's Delta
# (modules/hm-features/delta.nix).
#
# The URL has no /v1: both consumers append the version segment themselves.
# Only /v1 is reachable without the passkey, and it is gated by the API key,
# which luna's proxy accepts and opnix renders wherever a client or the proxy
# runs.
#
# Lives in myLib/ rather than modules/ because import-tree would turn it into a
# flake-parts module; it's a plain helper imported by relative path.
let
  site = import ./site.nix;
in {
  url = "https://cliproxy.${site.domain}";
  host = "cliproxy.${site.domain}";
  apiKeyFile = "/var/lib/opnix/secrets/cliProxyApiKey";
  # Declared by both the proxy and its clients; identical definitions merge.
  # Group-readable because both sides run as cramt.
  apiKeySecret = {
    reference = "op://Homelab/CliProxyAPI/apiKey";
    mode = "0640";
    group = "onepassword-secrets";
  };
}
