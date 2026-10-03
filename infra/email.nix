# Cloudflare Email Routing for the bare domain and one subdomain per
# forwarding address. The addresses (and so the subdomains) live in
# 1Password, which is why the record set is built in HCL at plan time
# rather than here.
{ config, lib, ... }:
let
  dkim = ''"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78k" "m4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB"'';
  spf = ''"v=spf1 include:_spf.mx.cloudflare.net ~all"'';
  mx = {
    mx1 = { prio = 48; content = "route1.mx.cloudflare.net"; };
    mx2 = { prio = 71; content = "route2.mx.cloudflare.net"; };
    mx3 = { prio = 25; content = "route3.mx.cloudflare.net"; };
  };

  # Nix's JSON is valid HCL, so static data drops straight into expressions.
  hcl = builtins.toJSON;

  # null stands for the bare domain, keyed `_`
  recordsFor = lib.concatStrings [
    "merge("
    "{ for k, r in ${hcl mx} : \"\${coalesce(prefix, \"_\")}\${k}\" => merge(r, { name = join(\".\", compact([prefix, var.domain])), type = \"MX\" }) },"
    "{ \"\${coalesce(prefix, \"_\")}spf\" = { name = join(\".\", compact([prefix, var.domain])), content = ${hcl spf}, type = \"TXT\" } }"
    ")"
  ];

  routingDependsOn = [ "cloudflare_dns_record.magic_email_dns" "cloudflare_email_routing_address.routing_addresses" ];
in
{
  resource.cloudflare_dns_record.magic_email_dns = {
    for_each = lib.concatStrings [
      "\${merge("
      "{ domainkey = { name = \"cf2024-1._domainkey.\${var.domain}\", content = ${hcl dkim}, type = \"TXT\" } },"
      "[for prefix in concat(keys(local.email_forwarding), [null]) : ${recordsFor}]..."
      ")}"
    ];
    zone_id = "\${local.zone_id}";
    content = "\${each.value.content}";
    name = "\${each.value.name}";
    proxied = false;
    ttl = 1;
    type = "\${each.value.type}";
    priority = "\${try(each.value.prio, null)}";
  };

  resource.cloudflare_email_routing_address.routing_addresses = {
    for_each = "\${local.email_forwarding}";
    account_id = "\${local.account_id}";
    email = "\${each.value}";
  };

  resource.cloudflare_email_routing_dns.subdomains = {
    depends_on = routingDependsOn;
    for_each = "\${local.email_forwarding}";
    zone_id = "\${local.zone_id}";
    name = "\${each.key}.\${var.domain}";
  };

  resource.cloudflare_email_routing_rule.main = {
    depends_on = routingDependsOn;
    for_each = "\${local.email_forwarding}";
    zone_id = "\${local.zone_id}";
    actions = [{ type = "forward"; value = [ "\${each.value}" ]; }];
    matchers = [{ field = "to"; type = "literal"; value = "\${each.key}@\${var.domain}"; }];
    enabled = true;
    priority = 0;
  };
}
