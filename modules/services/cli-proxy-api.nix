# Puts a user's cli-proxy-api pool (modules/hm-features/cli-proxy-api.nix) on a
# caddy vhost behind the authelia passkey, with no management key prompt on
# top: caddy overwrites Authorization with the real key, and the panel is
# patched to log in without asking.
#
# The key moves out of the user's auth-dir (0700 under a 0700 home) into a
# system-owned file that caddy's group can read, generated once by root. The
# proxy unit waits for it rather than racing to generate its own.
#
# The Anthropic API itself (/v1) is the exception to the passkey: Claude Code
# on the other hosts can't do a browser login, so those paths skip authelia
# and are gated by the pool's API key instead, shared with the clients through
# opnix (cliProxyApiKey).
{...}: {
  flake.nixosModules."services.cli-proxy-api" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.cli-proxy-api;
    keyDir = "/var/lib/cli-proxy-api-management";
    keyFile = "${keyDir}/key";
    caddyGroup = config.services.caddy.group;
  in {
    options.myNixOS.services.cli-proxy-api = {
      enable = lib.mkEnableOption "myNixOS.services.cli-proxy-api";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = "Home-users entry whose cli-proxy-api pool gets exposed.";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "cliproxy";
        description = "Caddy vhost. Gets its A record from caddy.subdomains.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.tmpfiles.settings."10-cli-proxy-api-management".${keyDir}.d = {
        user = cfg.user;
        group = caddyGroup;
        mode = "0750";
      };

      systemd.services.cli-proxy-api-management-key = {
        description = "Generate the cli-proxy-api management key shared with caddy";
        wantedBy = ["multi-user.target"];
        after = ["systemd-tmpfiles-setup.service"];
        serviceConfig.Type = "oneshot";
        script = ''
          if [ ! -s ${keyFile} ]; then
            umask 077
            ${lib.getExe pkgs.openssl} rand -hex 32 > ${keyFile}.new
            mv ${keyFile}.new ${keyFile}
          fi
          chown ${cfg.user}:${caddyGroup} ${keyFile}
          chmod 0640 ${keyFile}
        '';
      };

      home-manager.users.${cfg.user}.myHomeManager.cli-proxy-api = {
        enable = true;
        managementKeyFile = keyFile;
        apiKeyFile = config.services.onepassword-secrets.secretPaths.cliProxyApiKey;
        panelAutoLogin = true;
        # Only worth loading where something scrapes it.
        plugins = lib.mkIf config.services.prometheus.enable {
          cpa-prometheus.package = pkgs.cpa-prometheus;
        };
      };

      # CPA has no /metrics of its own; the plugin serves it on a management
      # route, behind the same key caddy injects. systemd hands prometheus a
      # copy, so the key stays readable by cramt and caddy only.
      myNixOS.services.metrics.localJobs.cli-proxy-api = {
        inherit (config.home-manager.users.${cfg.user}.myHomeManager.cli-proxy-api) port;
        path = "/v0/management/plugins/cpa-prometheus/metrics";
        extraConfig.authorization.credentials_file = "/run/credentials/prometheus.service/cli-proxy-api-management";
      };
      # promtool's full check stats credentials_file inside the build sandbox,
      # where the systemd credential can't exist yet.
      services.prometheus.checkConfig = lib.mkIf config.services.prometheus.enable "syntax-only";
      systemd.services.prometheus = lib.mkIf config.services.prometheus.enable {
        wants = ["cli-proxy-api-management-key.service"];
        after = ["cli-proxy-api-management-key.service"];
        serviceConfig.LoadCredential = ["cli-proxy-api-management:${keyFile}"];
      };

      myNixOS.services.caddy.serviceMap.${cfg.subdomain} = {
        inherit (config.home-manager.users.${cfg.user}.myHomeManager.cli-proxy-api) port;
        forward-auth = true;
        ungated-paths = ["/v1/*"];
        # Only the passkey-gated vhost gets this, so the panel's placeholder
        # key never reaches the bare port.
        reverse-proxy-config = ''
          header_up Authorization "Bearer {file.${keyFile}}"
        '';
      };

      # CPA's / is a JSON banner; the panel is what a browser wants. Merged into
      # the vhosts serviceMap generates; redir runs before handle, so ahead of
      # both the /v1 split and the passkey.
      services.caddy.virtualHosts = let
        caddyCfg = config.myNixOS.services.caddy;
      in
        lib.genAttrs (map (proto: "${proto}://${cfg.subdomain}.${caddyCfg.domain}") caddyCfg.protocol)
        (_: {
          extraConfig = ''
            redir / /management.html
          '';
        });
    };
  };
}
