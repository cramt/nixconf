# cramt's own Claude subscription pool: the cli-proxy-api on luna
# (modules/services/cli-proxy-api.nix), shared by every host's `claude` wrapper
# (modules/hm-features/claude-code.nix) and Zed's Delta
# (modules/hm-features/delta.nix). The employer's pool is a different thing, in
# myLib/agent-pool.nix.
#
# The URL has no /v1: both consumers append the version segment themselves.
# Only /v1 is reachable without the passkey, and it is gated by the API key,
# which opnix renders on every host from op://Homelab/CliProxyAPI/apiKey and
# luna's proxy accepts.
#
# Lives in myLib/ rather than modules/ for the same reason agent-pool.nix does.
let
  site = import ./site.nix;
in {
  url = "https://cliproxy.${site.domain}";
  host = "cliproxy.${site.domain}";
  apiKeyFile = "/var/lib/opnix/secrets/cliProxyApiKey";
}
