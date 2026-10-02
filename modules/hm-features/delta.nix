# Zed's Delta agent (pkgs.zed-delta, from the delta-nix overlay), wired to the
# local cli-proxy-api pool as a custom Anthropic provider so it draws on the
# same pooled subscriptions as `claude`.
#
# Delta writes ~/.config/delta/settings.json itself, so like
# ~/.claude/settings.json in claude-code.nix this can't be a home.file symlink:
# the provider entry is merged in on every activation and the rest of the file
# is left alone. Custom providers live under `native` — Delta silently ignores
# the key under `portable` or at the top level.
#
# Auth goes in as an `x-api-key` header rather than through Delta's API-key
# field, which only writes to the system keychain. That puts the proxy key in
# settings.json in plaintext, next to the 0600 keyfile it came from. Fine for a
# key that only gates 127.0.0.1. It is read at activation and never enters the
# store; the proxy generates it on its first start, so on a fresh host the
# provider shows up from the activation after that.
#
# Delta appends /v1/messages to base_url itself, so the base URL has no /v1.
{...}: {
  hmModules.features.delta = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.delta;
    proxyCfg = config.myHomeManager.cli-proxy-api;

    providerName = "cli-proxy-api";

    # Limits from Anthropic's model table. Delta needs them per model and the
    # pool's /v1/models doesn't report them. claude-sonnet-5-5 is served by
    # the pool but left out until its limits are published.
    models = [
      {
        id = "claude-opus-5-5";
        context_window = 1000000;
        max_output_tokens = 128000;
      }
      {
        id = "claude-opus-5";
        context_window = 1000000;
        max_output_tokens = 128000;
      }
      {
        id = "claude-fable-5-1";
        context_window = 1000000;
        max_output_tokens = 128000;
      }
      {
        id = "claude-sonnet-5";
        context_window = 1000000;
        max_output_tokens = 128000;
      }
      {
        id = "claude-haiku-4-5-20251001";
        context_window = 200000;
        max_output_tokens = 64000;
      }
    ];
    efforts = ["low" "medium" "high" "xhigh" "max"];

    provider = (pkgs.formats.json {}).generate "delta-pool-provider.json" {
      name = providerName;
      base_url = "http://127.0.0.1:${toString proxyCfg.port}";
      api_mode = "anthropic";
      models = map (m: m // {reasoning_efforts = efforts;}) models;
    };

    mergeSettings = pkgs.writeShellApplication {
      name = "delta-merge-settings";
      runtimeInputs = [pkgs.coreutils pkgs.jq];
      text = ''
        f="$HOME/.config/delta/settings.json"
        keyfile="$HOME/.cli-proxy-api/local-api-key"
        if [ ! -s "$keyfile" ]; then
          echo "delta-merge-settings: no $keyfile yet (cli-proxy-api hasn't started), skipping" >&2
          exit 0
        fi
        install -d "$HOME/.config/delta"
        # Refuse to clobber a file we can't parse — it's Delta's own state.
        if [ -e "$f" ]; then
          current=$(jq . "$f") || { echo "delta-merge-settings: $f is not valid JSON, skipping" >&2; exit 0; }
        else
          current='{"version": 1}'
        fi
        # Replace our entry by name, keep any providers added through the UI.
        printf '%s' "$current" | jq \
          --slurpfile p ${provider} \
          --rawfile key "$keyfile" '
            ($p[0] + {headers: [{name: "x-api-key", value: ($key | rtrimstr("\n"))}]}) as $ours
            | .native.custom_providers = ([(.native.custom_providers // [])[] | select(.name != $ours.name)] + [$ours])
          ' > "$f.new"
        chmod 600 "$f.new"
        mv "$f.new" "$f"
      '';
    };
  in {
    options.myHomeManager.delta.enable = lib.mkEnableOption "myHomeManager.delta";

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {home.packages = [pkgs.zed-delta];}
      (lib.mkIf proxyCfg.enable {
        home.activation.delta-settings = lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${lib.getExe mergeSettings}
        '';
      })
    ]);
  };
}
