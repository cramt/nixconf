# Terranix entrypoint for the Cloudflare infra, applied by `just deploy`
# (wired up in modules/flake/infra.nix).
#
# Secrets never enter the store: the wrapper reads them from 1Password and
# hands them over as TF_VAR_* / CLOUDFLARE_* env vars.
{ lib, ... }: {
  imports = [
    (lib.tf.provider "cloudflare_cloudflare")
    ./dns.nix
    ./email.nix
    ./workers.nix
  ];

  # A plain file on luna. The wrapper only ever runs tofu there, so nothing
  # else needs to reach it, and the local backend's file lock is enough to
  # serialize applies started from different machines.
  terraform.backend.local.path = "/vault/terraform/nixconf.tfstate";

  variable = {
    domain = { type = "string"; sensitive = true; };
    ip = { type = "string"; sensitive = true; };
    atproto = { type = "string"; sensitive = true; };
    atproto_hannah = { type = "string"; sensitive = true; };
    # Not sensitive itself, because its keys drive for_each, which refuses
    # sensitive values. local.email_forwarding hides the addresses instead.
    email_forwarding.type = "map(string)";
  };

  data.cloudflare_accounts.main.name = "cramt";
  data.cloudflare_zones.main.name = "\${var.domain}";

  locals = {
    account_id = "\${element(data.cloudflare_accounts.main.result, 0).id}";
    zone_id = "\${element(data.cloudflare_zones.main.result, 0).id}";
    email_forwarding = "\${{ for k, v in var.email_forwarding : k => sensitive(v) }}";
  };
}
