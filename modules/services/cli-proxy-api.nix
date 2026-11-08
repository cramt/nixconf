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
# op-secrets (cliProxyApiKey).
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
    m365 = config.myNixOS.services.m365-copilot-proxy;
    hmCfg = config.home-manager.users.${cfg.user};
    authDir = "${hmCfg.home.homeDirectory}/.cli-proxy-api";
    tokenDir = "/run/cli-proxy-api-tokens";
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

      myNixOS.secrets.cliProxyApiKey = (import ../../myLib/claude-pool.nix).apiKeySecret;

      home-manager.users.${cfg.user}.myHomeManager.cli-proxy-api = {
        enable = true;
        managementKeyFile = keyFile;
        apiKeyFile = config.myNixOS.secrets.cliProxyApiKey.path;
        panelAutoLogin = true;
        # M365 Copilot on the same host joins the pool as `m365/<model>`. The
        # prefix is load-bearing: it serves claude-* ids too, and unprefixed
        # those would get mixed into the subscription accounts' rotation.
        openai-compatibility = lib.mkIf m365.enable [
          {
            name = "m365";
            prefix = "m365";
            # One upstream behind one credential: cooling it after a failure
            # (M365 throws the odd InternalError) leaves nothing to fail over
            # to, so every client retry got an instant 503 instead of a fresh
            # attempt.
            disable-cooling = true;
            base-url = "http://127.0.0.1:${toString config.services.m365-copilot-proxy.port}/v1";
            models = map (name: {
              inherit name;
              alias = name;
            })
            m365.models;
          }
        ];
        # Only worth loading where something scrapes it.
        plugins = lib.mkIf config.services.prometheus.enable {
          cpa-prometheus.package = pkgs.cpa-prometheus;
        };
      };

      # A T3 Code server on this host, as the pool's own user, shows the pool's
      # limits under Usage. Same user only: the key file is cfg.user:caddy 0640.
      myNixOS.services.t3code.usageHub = lib.mkIf (config.myNixOS.services.t3code.enable && config.myNixOS.services.t3code.user == cfg.user) {
        url = "http://127.0.0.1:${toString config.home-manager.users.${cfg.user}.myHomeManager.cli-proxy-api.port}";
        managementKeyFile = keyFile;
        label = "Claude pool";
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

      # "Logged out" means the refresh token stopped working, and the only
      # place that shows is the access token's expiry in the account's auth
      # file: CPA rewrites it every ~4h, so a timestamp in the past means
      # refreshing failed. The plugin's auth_unavailable can't tell this apart
      # from an ordinary usage-limit cooldown, and its last_refresh lags the
      # file by hours. A system unit as cfg.user, because node_exporter runs
      # with ProtectHome and can't read auth-dir itself.
      systemd.services.cli-proxy-api-token-expiry = lib.mkIf config.myNixOS.services.alerts.enable {
        description = "Export cli-proxy-api OAuth token expiry for prometheus";
        path = [pkgs.jq pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          RuntimeDirectory = baseNameOf tokenDir;
          RuntimeDirectoryMode = "0755";
          # Oneshot: without this the file vanishes the moment it's written.
          RuntimeDirectoryPreserve = true;
        };
        script = ''
          out=${tokenDir}/tokens.prom
          {
            echo '# HELP cli_proxy_api_token_expiry_timestamp_seconds When the account access token expires; in the past means refresh is failing.'
            echo '# TYPE cli_proxy_api_token_expiry_timestamp_seconds gauge'
            for f in ${authDir}/*.json; do
              [ -e "$f" ] || continue
              # jq's fromdateiso8601 rejects the +01:00 offsets CPA writes.
              jq -r 'select(.type != null and .expired != null) | [.type, .email // "unknown", .expired] | @tsv' "$f" |
                while IFS=$'\t' read -r provider email expired; do
                  echo "cli_proxy_api_token_expiry_timestamp_seconds{provider=\"$provider\",email=\"$email\"} $(date -d "$expired" +%s)"
                done
            done
          } > "$out.tmp"
          mv "$out.tmp" "$out"
        '';
      };
      systemd.timers.cli-proxy-api-token-expiry = lib.mkIf config.myNixOS.services.alerts.enable {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1m";
          OnUnitActiveSec = "1m";
        };
      };
      myNixOS.services.metrics.textfiles = lib.mkIf config.myNixOS.services.alerts.enable {
        cli-proxy-api-tokens = "${tokenDir}/tokens.prom";
      };
      myNixOS.services.alerts.alertRules.cli-proxy-api = [
        {
          alert = "ClaudeAccountLoggedOut";
          expr = "cli_proxy_api_token_expiry_timestamp_seconds < time()";
          "for" = "15m";
          annotations = {
            summary = "{{ $labels.email }} got logged out of the Claude pool";
            description = "Token expired and CPA couldn't refresh it. Log back in on luna: `agent-accounts add {{ $labels.provider }}`";
          };
        }
        {
          # Deleted auth file: the series just stops, which `<` never sees.
          alert = "ClaudeAccountGone";
          expr = "max_over_time(cli_proxy_api_token_expiry_timestamp_seconds[1d]) unless cli_proxy_api_token_expiry_timestamp_seconds";
          "for" = "5m";
          annotations.summary = "{{ $labels.email }} vanished from the Claude pool";
        }
      ];

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
