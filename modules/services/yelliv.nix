# yelliv — OpenClaw gateway running in an isolated NixOS container that
# talks to the host's llama-cpp HTTP API.
{ inputs, ... }: {
  flake.nixosModules."services.yelliv" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.services.yelliv;
    hostAddress = "10.233.42.1";
    localAddress = "10.233.42.2";
    gatewayPort = 18789;
  in {
    options.myNixOS.services.yelliv = {
      enable = lib.mkEnableOption "myNixOS.services.yelliv";
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/yelliv";
        description = "Host state dir bind-mounted into the container at /var/lib/openclaw";
      };
      documentsDir = lib.mkOption {
        type = lib.types.path;
        default = ../../yelliv-documents;
        description = "Directory with AGENTS/SOUL/TOOLS documents; bind-mounted read-only";
      };
      llamaBaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://${hostAddress}:11434/v1";
        description = "OpenAI-compatible base URL for the host's llama-cpp instance";
      };
      llamaModelId = lib.mkOption {
        type = lib.types.str;
        default = "qwen3-14b";
        description = "Model id exposed by llama-swap on the host";
      };
      hostPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Host port forwarded to the gateway (null = auto via port-selector)";
      };
      discord = {
        enable = lib.mkEnableOption "Discord channel for OpenClaw";
        guildId = lib.mkOption {
          type = lib.types.str;
          description = "Discord server (guild) ID";
        };
        userId = lib.mkOption {
          type = lib.types.str;
          description = "Your Discord user ID (for allowlist)";
        };
      };
    };
    config = lib.mkIf cfg.enable (let
      resolvedHostPort =
        if cfg.hostPort != null
        then cfg.hostPort
        else config.port-selector.ports.yelliv;
    in {
      port-selector.auto-assign = lib.optional (cfg.hostPort == null) "yelliv";
      port-selector.set-ports = lib.optionalAttrs (cfg.hostPort != null) {
        "${toString cfg.hostPort}" = "yelliv";
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root -"
      ];

      # Allow the container to reach the host's llama-cpp port.
      networking.firewall.interfaces."ve-yelliv".allowedTCPPorts = [ 11434 ];
      networking.firewall.allowedTCPPorts = [ resolvedHostPort ];

      # Masquerade outbound traffic from the container's veth so the guest
      # can pull npm packages (for plugins like acpx that spawn `npx …`) and
      # reach any other external endpoint via saturn's uplink.
      networking.nat = {
        enable = true;
        internalInterfaces = [ "ve-yelliv" ];
        externalInterface = "enp6s0";
      };

      # Make `http://127.0.0.1:<forwarded port>` reach the container from the
      # host itself. nixos-containers' forwardPorts installs DNAT in PREROUTING
      # only; locally-originated loopback traffic skips that chain. Fix via an
      # OUTPUT-chain DNAT plus route_localnet so the kernel lets a 127.0.0.1
      # packet leave lo toward the veth.
      boot.kernel.sysctl = {
        "net.ipv4.conf.lo.route_localnet" = 1;
        "net.ipv4.conf.all.route_localnet" = 1;
      };
      networking.nftables.tables."yelliv-loopback" = {
        family = "ip";
        content = ''
          chain output {
            type nat hook output priority mangle;
            ip daddr 127.0.0.0/8 tcp dport ${toString resolvedHostPort} \
              dnat to ${localAddress}:${toString gatewayPort} \
              comment "yelliv loopback reflection"
          }
          # After DNAT the packet exits via ve-yelliv with source 127.0.0.1,
          # which the container can't route back. SNAT to the host-side veth
          # IP so the container sees the host as the client and the reply
          # returns through conntrack.
          chain postrouting {
            type nat hook postrouting priority srcnat;
            oifname "ve-yelliv" ip saddr 127.0.0.0/8 ip daddr ${localAddress} \
              snat to ${hostAddress} \
              comment "yelliv loopback snat"
          }
        '';
      };

      containers.yelliv = {
        autoStart = true;
        ephemeral = false;
        privateNetwork = true;
        inherit hostAddress localAddress;
        forwardPorts = [{
          hostPort = resolvedHostPort;
          containerPort = gatewayPort;
          protocol = "tcp";
        }];
        bindMounts = {
          "/etc/yelliv/documents" = {
            hostPath = "${cfg.documentsDir}";
            isReadOnly = true;
          };
          "/var/lib/openclaw" = {
            hostPath = cfg.dataDir;
            isReadOnly = false;
          };
        } // lib.optionalAttrs cfg.discord.enable {
          "/run/secrets/discord-bot-token" = {
            hostPath = config.services.onepassword-secrets.secretPaths.discordBotToken;
            isReadOnly = true;
          };
        };
        config = { config, lib, pkgs, ... }: {
          system.stateVersion = "25.11";

          imports = [
            inputs.nix-openclaw.nixosModules.openclaw-gateway
          ];

          nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];
          nixpkgs.config.allowUnfree = true;

          networking.firewall.allowedTCPPorts = [ gatewayPort ];
          networking.useHostResolvConf = lib.mkForce false;
          networking.defaultGateway = hostAddress;
          networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
          services.resolved.enable = true;

          # Node + git so the acpx plugin can `npx @zed-industries/codex-acp`
          # instead of crashing with "Failed to spawn agent command".
          environment.systemPackages = with pkgs; [
            nodejs_22
            git
          ];

          # Mirror gateway stdout/stderr to the journal so the host can
          # `journalctl --machine=yelliv -u openclaw-gateway` without chasing
          # the log file inside the state dir.
          # Also generate a random gateway auth token on first boot (bind=lan
          # refuses to run without one); persisted in the bind-mounted state
          # dir so it survives container rebuilds.
          systemd.services.openclaw-gateway.serviceConfig = {
            StandardOutput = lib.mkForce "journal";
            StandardError = lib.mkForce "journal";
            ExecStartPre = lib.mkBefore [
              ("+" + pkgs.writeShellScript "yelliv-pre-start" ''
                set -euo pipefail

                # Ensure the state dir is world-readable so the host user
                # can read the token file without sudo.
                chmod 755 /var/lib/openclaw

                # Generate a random gateway auth token on first boot and
                # persist it in the bind-mounted state dir. bind=lan refuses
                # to run without one.
                envFile=/var/lib/openclaw/token.env
                if [[ ! -s "$envFile" ]]; then
                  umask 077
                  token=$(head -c 32 /dev/urandom | base64 | tr -d '=+/' | head -c 48)
                  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$token" > "$envFile"
                  chown openclaw:openclaw "$envFile"
                fi
                chmod 644 "$envFile"

                # Sync declarative AGENTS/SOUL/TOOLS docs into a writable
                # workspace so plugins (e.g. acpx) can create `state/`
                # subdirs next to them. Files removed from the repo aren't
                # pruned here — if you need a clean slate, rm the dir.
                workspace=/var/lib/openclaw/workspace
                install -d -o openclaw -g openclaw -m 0755 "$workspace"
                for f in /etc/yelliv/documents/*; do
                  [[ -f "$f" ]] || continue
                  install -o openclaw -g openclaw -m 0644 "$f" "$workspace/$(basename "$f")"
                done

                # Write discord bot token env file from the bind-mounted secret.
                discordEnv=/var/lib/openclaw/discord.env
                if [[ -f /run/secrets/discord-bot-token ]]; then
                  printf 'DISCORD_BOT_TOKEN=%s\n' "$(cat /run/secrets/discord-bot-token)" > "$discordEnv"
                  chown openclaw:openclaw "$discordEnv"
                  chmod 600 "$discordEnv"
                fi

                # Seed auth-profiles.json with a dummy api_key for the local
                # llama-cpp provider. llama-cpp ignores the key but the
                # gateway refuses to route traffic without a profile entry.
                agentDir=/var/lib/openclaw/agents/main/agent
                install -d -o openclaw -g openclaw -m 0700 "$agentDir"
                authFile="$agentDir/auth-profiles.json"
                if [[ ! -s "$authFile" ]]; then
                  umask 077
                  ${pkgs.jq}/bin/jq -n \
                    '{version: 1, profiles: {"saturn-llama-cpp:default": {type: "api_key", provider: "saturn-llama-cpp", key: "local-no-auth"}}}' \
                    > "$authFile"
                  chown openclaw:openclaw "$authFile"
                  chmod 600 "$authFile"
                fi
              '')
            ];
          };

          services.openclaw-gateway = {
            enable = true;
            port = gatewayPort;
            stateDir = "/var/lib/openclaw";
            environmentFiles = [
              "-/var/lib/openclaw/token.env"
            ] ++ lib.optional cfg.discord.enable "-/var/lib/openclaw/discord.env";
            config = {
              gateway = {
                mode = "local";
                bind = "lan";
                auth.mode = "token";
                controlUi.allowedOrigins = [
                  "http://localhost:${toString resolvedHostPort}"
                  "http://127.0.0.1:${toString resolvedHostPort}"
                  "http://${hostAddress}:${toString resolvedHostPort}"
                  "http://192.168.178.23:${toString resolvedHostPort}"
                  "http://saturn:${toString resolvedHostPort}"
                  "http://saturn.local:${toString resolvedHostPort}"
                ];
              };
              models = {
                mode = "merge";
                providers.saturn-llama-cpp = {
                  api = "openai-completions";
                  baseUrl = cfg.llamaBaseUrl;
                  apiKey = "local-no-auth";
                  models = [{
                    id = cfg.llamaModelId;
                    name = cfg.llamaModelId;
                  }];
                };
              };
              agents.defaults.workspace = "/var/lib/openclaw/workspace";
            } // lib.optionalAttrs cfg.discord.enable {
              channels.discord = {
                enabled = true;
                token = {
                  source = "env";
                  provider = "default";
                  id = "DISCORD_BOT_TOKEN";
                };
                dmPolicy = "pairing";
                groupPolicy = "allowlist";
                guilds.${cfg.discord.guildId} = {
                  requireMention = false;
                  users = [ cfg.discord.userId ];
                };
              };
            };
          };
        };
      };

    });
  };
}
