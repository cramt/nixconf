# opencode — same shape as modules/hm-features/claude-code.nix: the shared
# global agent instructions, the same skill libraries, and a pooled endpoint
# instead of a per-machine login.
#
# The difference is whose pool. `claude` talks to the cli-proxy-api running on
# this machine (127.0.0.1, see modules/hm-features/cli-proxy-api.nix); opencode
# talks to the employer's, which is remote and needs a URL and an API key. Both
# live in one 1Password field that opnix renders to
# /var/lib/opnix/secrets/opencodeEnv as:
#
#   OPENCODE_URL=https://<host>/v1        # include /v1 — it's the anthropic base
#   OPENCODE_API_KEY=<key>
#
# opencode.json refers to them as {env:...}, and the `opencode` wrapper sources
# that file so they resolve. Going through env rather than baking the values
# into settings keeps them out of the world-readable nix store.
{inputs, ...}: {
  hmModules.features.opencode = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.opencode;

    skills = import ../../myLib/agent-skills.nix {inherit lib pkgs inputs;};

    envFile = "/var/lib/opnix/secrets/opencodeEnv";

    # Every model the work pool serves. They all arrive over the pool's
    # Anthropic-shaped endpoint, so the non-Claude ones are declared under the
    # `anthropic` provider too — the pool does not alias them onto claude-*,
    # and models.dev has no entry to look them up from.
    poolModels = {
      "claude-opus-5" = "Claude Opus 5";
      "claude-opus-4-8" = "Claude Opus 4.8";
      "claude-opus-4-7" = "Claude Opus 4.7";
      "claude-opus-4-6" = "Claude Opus 4.6";
      "claude-sonnet-5" = "Claude Sonnet 5";
      "claude-fable-5" = "Claude Fable 5";
      "gpt-5.6-luna" = "GPT-5.6 Luna";
      "gpt-5.6-sol" = "GPT-5.6 Sol";
      "gpt-5.6-terra" = "GPT-5.6 Terra";
      "deepseek-v4-flash" = "DeepSeek V4 Flash";
      "qwen3.8-max" = "Qwen3.8 Max";
    };

    # hiPrio to win over the plain binary `programs.opencode` installs.
    # Sourcing is unconditional-but-tolerant: a host whose opnix render hasn't
    # landed yet should still get a usable TUI (and a pointer at why it can't
    # reach the pool) rather than an `opencode` that refuses to launch.
    opencodeWrapper = lib.hiPrio (pkgs.writeShellScriptBin "opencode" ''
      if [ -r ${envFile} ]; then
        set -a
        . ${envFile}
        set +a
      else
        echo "opencode: cannot read ${envFile} — the work pool is not configured here." >&2
        echo "          myNixOS.opnix-secrets.enable must be on, and you must be in the" >&2
        echo "          onepassword-secrets group (re-login after the first deploy)." >&2
      fi

      exec ${lib.getExe pkgs.opencode} "$@"
    '');

    skillAttrs = entries: lib.listToAttrs (map (s: lib.nameValuePair s.name s.path) entries);
  in {
    options.myHomeManager.opencode = {
      enable = lib.mkEnableOption "myHomeManager.opencode";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + opencode skill"
        // {default = true;};
      pstack.enable =
        lib.mkEnableOption "vendored pstack judgment skills (unslop, type-system-discipline, technical-writing, …)"
        // {default = true;};
      mattpocock.enable =
        lib.mkEnableOption "mattpocock/skills engineering-process library (spec → tickets → triage → implement → review)"
        // {default = true;};
      mtg-commander.enable =
        lib.mkEnableOption "MTG Commander deckbuilding skill + `scryfall` bulk-data CLI"
        // {default = true;};
    };

    config = lib.mkIf cfg.enable {
      home.packages =
        [opencodeWrapper]
        ++ lib.optional cfg.mtg-commander.enable skills.scryfall
        ++ lib.optional cfg.agent-browser.enable skills.agent-browser;

      programs.opencode = {
        enable = true;

        # Same file Claude Code gets as ~/.claude/CLAUDE.md and pi gets as
        # ~/.pi/agent/AGENTS.md — one source of truth so the agents can't
        # disagree about what this machine is.
        context = ./global-agent-instructions.md;

        settings = {
          model = "anthropic/claude-opus-5";

          # Nix owns the binary; opencode's self-update would try to write into
          # the read-only store and fail on every launch.
          autoupdate = false;

          provider.anthropic = {
            options = {
              baseURL = "{env:OPENCODE_URL}";
              apiKey = "{env:OPENCODE_API_KEY}";
            };
            models = lib.mapAttrs (_: name: {inherit name;}) poolModels;
          };
        };

        skills =
          lib.optionalAttrs cfg.pstack.enable (skillAttrs skills.pstack)
          // lib.optionalAttrs cfg.mattpocock.enable (skillAttrs skills.mattpocock)
          // skillAttrs [skills.status]
          // lib.optionalAttrs cfg.mtg-commander.enable (skillAttrs [skills.mtg-commander])
          # The upstream SKILL.md is a discovery stub telling the agent to run
          # `agent-browser skills get core`, so the version-matched content
          # comes from the binary at runtime rather than from the store.
          // lib.optionalAttrs cfg.agent-browser.enable {
            agent-browser = "${skills.agent-browser}/share/agent-browser/skills/agent-browser/SKILL.md";
          };
      };
    };
  };
}
