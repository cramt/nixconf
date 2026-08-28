# opencode — same shape as modules/hm-features/claude-code.nix: the shared
# global agent instructions, the same skill libraries, and a pooled endpoint
# instead of a per-machine login.
#
# The difference is whose pool. `claude` talks to the cli-proxy-api running on
# this machine (127.0.0.1, see modules/hm-features/cli-proxy-api.nix); opencode
# talks to the employer's, which is remote and needs a URL and an API key —
# both from opnix; myLib/agent-pool.nix says where they come from and why they
# never enter the store. pi and omp read the same two files.
#
# opencode is the one consumer that wants the stored URL verbatim, /v1 and all:
# it hands options.baseURL to the anthropic provider whole, unlike Claude Code's
# ANTHROPIC_BASE_URL (and omp's), which appends the version segment itself.
#
# opencode.json refers to both as {env:...}, and the `opencode` wrapper exports
# them from those files. Going through env rather than baking the values into
# settings keeps them out of the world-readable nix store.
{inputs, ...}: {
  hmModules.features.opencode = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.opencode;

    skills = import ../../myLib/agent-skills.nix {inherit lib pkgs inputs;};

    pool = import ../../myLib/agent-pool.nix {inherit lib;};
    inherit (pool) urlFile apiKeyFile;

    # hiPrio to win over the plain binary `programs.opencode` installs.
    # Tolerant of a missing render: a host whose opnix secrets haven't landed
    # yet should still get a usable TUI (and a pointer at why it can't reach the
    # pool) rather than an `opencode` that refuses to launch. The values are
    # read rather than sourced — they're data, not shell.
    opencodeWrapper = lib.hiPrio (pkgs.writeShellScriptBin "opencode" ''
      if [ -r ${urlFile} ] && [ -r ${apiKeyFile} ]; then
        OPENCODE_URL=$(< ${urlFile})
        OPENCODE_API_KEY=$(< ${apiKeyFile})
        export OPENCODE_URL OPENCODE_API_KEY
      else
        echo "opencode: cannot read ${urlFile} / ${apiKeyFile} —" >&2
        echo "          the work pool is not configured here. myNixOS.opnix-secrets.enable" >&2
        echo "          must be on, and you must be in the onepassword-secrets group" >&2
        echo "          (re-login after the first deploy)." >&2
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
          model = "anthropic/${pool.defaultModel}";

          # Nix owns the binary; opencode's self-update would try to write into
          # the read-only store and fail on every launch.
          autoupdate = false;

          # opencode auto-loads its own Zen gateways, which serve most of the
          # same model names the pool does — so the picker shows two entries
          # per model with nothing to tell them apart. The pool is the only
          # route this machine is meant to use.
          disabled_providers = ["opencode" "opencode-go"];

          provider.anthropic = {
            options = {
              baseURL = "{env:OPENCODE_URL}";
              apiKey = "{env:OPENCODE_API_KEY}";
            };
            models = lib.mapAttrs (_: name: {inherit name;}) pool.allModelNames;
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
