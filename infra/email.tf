resource "cloudflare_dns_record" "magic_email_dns" {
  for_each = merge({
    domainkey = {
      name    = "cf2024-1._domainkey.${local.secrets.domain}"
      content = <<CONTENT
"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78k" "m4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB"
      CONTENT
      type    = "TXT"
    }

    }, [for prefix in concat(keys(local.secrets.email_forwarding), [null]) : {
      "${coalesce(prefix, "_")}mx3" = {
        prio    = 25
        content = "route3.mx.cloudflare.net"
        name    = join(".", compact([prefix, local.secrets.domain]))
        type    = "MX"
      }
      "${coalesce(prefix, "_")}mx2" = {
        prio    = 71
        content = "route2.mx.cloudflare.net"
        name    = join(".", compact([prefix, local.secrets.domain]))
        type    = "MX"
      }
      "${coalesce(prefix, "_")}mx1" = {
        prio    = 48
        content = "route1.mx.cloudflare.net"
        name    = join(".", compact([prefix, local.secrets.domain]))
        type    = "MX"
      }
      "${coalesce(prefix, "_")}spf" = {

        name    = join(".", compact([prefix, local.secrets.domain]))
        content = <<CONTENT
"v=spf1 include:_spf.mx.cloudflare.net ~all"
      CONTENT
        type    = "TXT"
      },
  }]...)

  zone_id  = local.zone_id
  content  = try(each.value.content, each.key)
  name     = each.value.name
  proxied  = false
  ttl      = 1
  type     = each.value.type
  priority = try(each.value.prio, null)

}


resource "cloudflare_email_routing_address" "routing_addresses" {
  for_each   = local.secrets.email_forwarding
  account_id = local.account.id
  email      = each.value
}

resource "cloudflare_email_routing_dns" "subdomains" {
  depends_on = [cloudflare_dns_record.magic_email_dns, cloudflare_email_routing_address.routing_addresses]
  for_each   = local.secrets.email_forwarding
  zone_id    = local.zone_id
  name       = "${each.key}.${local.secrets.domain}"
}

resource "cloudflare_email_routing_rule" "main" {
  depends_on = [cloudflare_dns_record.magic_email_dns, cloudflare_email_routing_address.routing_addresses]
  for_each   = local.secrets.email_forwarding
  zone_id    = local.zone_id
  actions = [{
    type  = "forward"
    value = [each.value]
  }]
  matchers = [{
    field = "to"
    type  = "literal"
    value = "${each.key}@${local.secrets.domain}"
  }]
  enabled  = true
  priority = 0
}
