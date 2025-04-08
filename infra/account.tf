data "cloudflare_accounts" "main" {
  name = "cramt"
}
locals {
  account = element(data.cloudflare_accounts.main.result, 0)
}
