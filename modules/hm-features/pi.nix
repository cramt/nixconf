# pi — same shape as modules/hm-features/claude-code.nix and opencode.nix: the
# shared global agent instructions, the same skill libraries, and the work pool
# (myLib/agent-pool.nix) instead of a per-machine login.
#
# The auth is opencode's, plumbed the way pi wants it rather than the way
# opencode does:
#
#   key   ANTHROPIC_API_KEY, which pi's built-in `anthropic` provider resolves
#         into an `x-api-key` header — the same header opencode's provider
#         sends, so the pool sees an identical request.
#   URL   models.json `providers.anthropic.baseUrl`. pi has no env equivalent
#         (unlike Claude Code's ANTHROPIC_BASE_URL, which omp also honours), so
#         the wrapper renders that one file at launch from the secret. It hands
#         the value straight to @anthropic-ai/sdk, which appends /v1/messages
#         itself — hence the trailing /v1 gets stripped off the stored URL.
#
# ANTHROPIC_AUTH_TOKEN has to be cleared: pi prefers it over ANTHROPIC_API_KEY
# and sends it as `Authorization: Bearer`, so a pi launched from inside a
# `claude` session (whose wrapper exports the local cli-proxy-api token) would
# otherwise present that machine-local token to the work pool.
{inputs, ...}: {
  hmModules.features.pi = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.pi;

    pool = import ../../myLib/agent-pool.nix {inherit lib;};
    skills = import ../../myLib/agent-skills.nix {inherit lib pkgs inputs;};

    # Everything about models.json except the pool's address, which is the one
    # value that may not sit in the store. The wrapper substitutes it in.
    #
    # Only the non-Claude half of the pool is declared: pi's built-in catalog
    # already carries claude-opus-5 and friends, and an entry here would shadow
    # upstream's maintained limits with our guesses. The flip side is that the
    # catalog also lists Claude models this pool does not serve (haiku-4-5,
    # opus-4-5, …) — pi has no allowlist to hide them with, so picking one just
    # fails at request time.
    modelsTemplate = pkgs.writeText "pi-models.json.in" (builtins.toJSON {
      providers.anthropic = {
        baseUrl = "@POOL_BASE_URL@";
        models =
          lib.mapAttrsToList (id: m: {
            inherit id;
            inherit (m) name contextWindow maxTokens;
            api = "anthropic-messages";
            reasoning = true;
            input = ["text" "image"];
          })
          pool.extraModels;
      };
    });

    # hiPrio to win over the plain `pi` the upstream module installs (which is
    # itself a wrapper — cfg.finalPackage — carrying the --skill flags and the
    # settings.json merge, so it is what we exec).
    #
    # Tolerant of a missing render: a host whose opnix secrets haven't landed
    # yet should still get a usable TUI (and a pointer at why it can't reach the
    # pool) rather than a `pi` that refuses to launch. The values are read
    # rather than sourced — they're data, not shell.
    piCfg = config.programs.pi.coding-agent;
    piWrapper = lib.hiPrio (pkgs.writeShellScriptBin "pi" ''
      export PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

      # Never present a nested `claude` session's local pool token upstream.
      unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL

      if [ -r ${pool.urlFile} ] && [ -r ${pool.apiKeyFile} ]; then
        ANTHROPIC_API_KEY=$(< ${pool.apiKeyFile})
        export ANTHROPIC_API_KEY

        # The SDK appends /v1/messages to whatever it is given, so the stored
        # URL's own /v1 has to come off or every request lands on /v1/v1/....
        pool_url=$(< ${pool.urlFile})
        pool_url=''${pool_url%/}
        pool_url=''${pool_url%/v1}

        mkdir -p "$PI_CODING_AGENT_DIR"
        umask 077
        ${lib.getExe pkgs.gnused} "s|@POOL_BASE_URL@|$pool_url|" ${modelsTemplate} \
          > "$PI_CODING_AGENT_DIR/models.json"
      else
        echo "pi: cannot read ${pool.urlFile} / ${pool.apiKeyFile} —" >&2
        echo "    the work pool is not configured here. myNixOS.opnix-secrets.enable" >&2
        echo "    must be on, and you must be in the onepassword-secrets group" >&2
        echo "    (re-login after the first deploy)." >&2
      fi

      exec ${lib.getExe piCfg.finalPackage} "$@"
    '');
  in {
    imports = [inputs.pi.homeModules.default];

    options.myHomeManager.pi = {
      enable = lib.mkEnableOption "myHomeManager.pi";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + pi skill"
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
        [piWrapper]
        ++ lib.optional cfg.mtg-commander.enable skills.scryfall
        ++ lib.optional cfg.agent-browser.enable skills.agent-browser;

      programs.pi.coding-agent = {
        enable = true;

        # ~/.pi/agent/settings.json. pi mutates this file at runtime (e.g.
        # lastChangelogVersion), so the module jq-merges our declared values
        # over it on every launch — declared keys stay authoritative.
        settings = {
          defaultProvider = "anthropic";
          defaultModel = pool.defaultModel;
          defaultThinkingLevel = "medium";

          compaction.enabled = true;

          enableInstallTelemetry = false;
        };

        # NB: models.json is deliberately NOT set through the module's `models`
        # option. Its installer only writes the file when one isn't already
        # there, so a pool URL change would never reach an existing checkout —
        # and the value isn't a store path to begin with. The wrapper owns it.

        # Each becomes a repeated `--skill <path>`. Skills-only installs — no
        # plugin registration, no session hook — so they stay as declarative and
        # disposable as the ones claude-code.nix symlinks into ~/.claude/skills.
        skills =
          lib.optionals cfg.pstack.enable (map (s: s.path) skills.pstack)
          ++ lib.optionals cfg.mattpocock.enable (map (s: s.path) skills.mattpocock)
          ++ [skills.status.path]
          ++ lib.optional cfg.mtg-commander.enable skills.mtg-commander.path
          # The upstream SKILL.md is a discovery stub telling the agent to run
          # `agent-browser skills get core`, so the version-matched content comes
          # from the binary at runtime rather than from the store.
          ++ lib.optional cfg.agent-browser.enable
          "${skills.agent-browser}/share/agent-browser/skills/agent-browser/SKILL.md";
      };

      # pi's GLOBAL instruction file, loaded before any project AGENTS.md. Same
      # source Claude Code gets as ~/.claude/CLAUDE.md and opencode gets as its
      # context file — one source of truth so the agents can't disagree about
      # what this machine is.
      home.file.".pi/agent/AGENTS.md".source = ./global-agent-instructions.md;
    };
  };
}
