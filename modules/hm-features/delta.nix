# Zed's Delta agent (pkgs.zed-delta, from the delta-nix overlay), wired to the
# cli-proxy-api pool on luna (myLib/claude-pool.nix) as a custom Anthropic
# provider so it draws on the same pooled subscriptions as `claude`.
#
# Delta writes ~/.config/delta/settings.json itself, so like
# ~/.claude/settings.json in claude-code.nix this can't be a home.file symlink:
# the provider entry is merged in on every activation and the rest of the file
# is left alone. Custom providers live under `native` — Delta silently ignores
# the key under `portable` or at the top level.
#
# Auth goes in as an `x-api-key` header rather than through Delta's API-key
# field, which only writes to the system keychain. That puts the proxy key in
# settings.json in plaintext (0600). It is read at activation from the opnix
# file and never enters the store; on a fresh host the provider shows up from
# the first activation after opnix has rendered it.
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
    pool = import ../../myLib/claude-pool.nix;

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
      base_url = pool.url;
      api_mode = "anthropic";
      models = map (m: m // {reasoning_efforts = efforts;}) models;
    };

    mergeSettings = pkgs.writeShellApplication {
      name = "delta-merge-settings";
      runtimeInputs = [pkgs.coreutils pkgs.jq];
      text = ''
        f="$HOME/.config/delta/settings.json"
        keyfile=${pool.apiKeyFile}
        if [ ! -r "$keyfile" ] || [ ! -s "$keyfile" ]; then
          echo "delta-merge-settings: cannot read $keyfile (opnix not rendered yet?), skipping" >&2
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
      {
        home.activation.delta-settings = lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${lib.getExe mergeSettings}
        '';
      }
    ]);
  };
}
