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

  # Connection string comes from PG_CONN_STR; the database lives on luna
  # (myNixOS.services.terraform_remote_backend).
  terraform.backend.pg = { };

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
