data "external" "waker_build" {
  program = ["sh", "-c", "pnpm i &> /dev/null && npx wrangler deploy --dry-run --outdir dist --minify &> /dev/null && echo '{}'"]

  working_dir = "${path.module}/root"
}

resource "cloudflare_workers_script" "root" {
  account_id          = local.account.id
  depends_on          = [data.external.waker_build]
  script_name         = "root"
  content             = file("${path.module}/root/dist/index.js")
  compatibility_date  = "2025-04-08"
  compatibility_flags = ["nodejs_compat_v2"]
  main_module         = "worker.js"
}

resource "cloudflare_workers_custom_domain" "root" {
  account_id  = local.account.id
  environment = "production"
  hostname    = local.secrets.domain
  service     = cloudflare_workers_script.root.script_name
  zone_id     = local.zone_id
}
