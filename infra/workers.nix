{ config, lib, pkgs, ... }:
let
  # `name` is both the source dir under infra/ and the worker's script name
  worker = { resource, name, hash, hostname }: {
    resource.cloudflare_workers_script.${resource} = {
      account_id = "\${local.account_id}";
      script_name = name;
      content = "\${file(\"${pkgs.callPackage ./worker.nix { inherit name hash; }}\")}";
      compatibility_date = "2025-04-08";
      compatibility_flags = [ "nodejs_compat_v2" ];
      main_module = "worker.js";
    };

    resource.cloudflare_workers_custom_domain.${resource} = {
      account_id = "\${local.account_id}";
      environment = "production";
      inherit hostname;
      service = config.resource.cloudflare_workers_script.${resource} "script_name";
      zone_id = "\${local.zone_id}";
    };
  };
in
{
  config = lib.mkMerge [
    (worker {
      resource = "root";
      name = "root";
      hash = "sha256-4iS8GMIweILlPsi1lWPzXaV9vWVAY7HeMX/WhAyI6nE=";
      hostname = "\${var.domain}";
    })
    (worker {
      resource = "qr_codes";
      name = "qr-codes";
      hash = "sha256-ioLQaZcapTFryjd/4Fpe4elBd1F3x9bJMh8rgKqjMlw=";
      hostname = "qr-codes.\${var.domain}";
    })
  ];
}
