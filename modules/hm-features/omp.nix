# omp (can1357's fork of pi) — same shape as modules/hm-features/claude-code.nix
# and opencode.nix: the shared global agent instructions, the same skill
# libraries, and the work pool (myLib/agent-pool.nix) instead of a per-machine
# login.
#
# omp is the one agent here that takes the pool purely through the environment,
# Claude Code style: ANTHROPIC_BASE_URL for the endpoint (it strips the stored
# URL's trailing /v1 itself before appending /v1/messages) and ANTHROPIC_API_KEY
# for the credential, which it sends as both `x-api-key` and `Authorization:
# Bearer`. No config file has to hold either value.
#
# ANTHROPIC_AUTH_TOKEN has to be cleared: an omp launched from inside a `claude`
# session would otherwise inherit that wrapper's local cli-proxy-api token and
# present it to the work pool.
#
# The cost of the env route is that only omp's built-in Anthropic catalog is
# selectable — the pool's gpt-5.6-*/deepseek/qwen models would need a models.yml
# entry, and models.yml refuses `models:` without a provider-level `apiKey`,
# which then serves *every* anthropic model over `Authorization: Bearer` alone.
# The pool is only known to accept `x-api-key` (that is what opencode sends), so
# the extra models wait until Bearer is confirmed working against it. pi has no
# such constraint and does list them; see modules/hm-features/pi.nix.
{inputs, ...}: {
  hmModules.features.omp = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.omp;

    pool = import ../../myLib/agent-pool.nix {inherit lib;};
    skills = import ../../myLib/agent-skills.nix {inherit lib pkgs inputs;};

    # omp has no `--skill <path>` flag (only `--skills=<glob>` for filtering), so
    # skills arrive through skills.customDirectories, which scans exactly one
    # level deep for <dir>/<name>/SKILL.md. Entries whose store path is the
    # SKILL.md itself get that layout built around them here.
    skillEntries =
      lib.optionals cfg.pstack.enable (map (s: {
          name = "${s.name}/SKILL.md";
          path = "${s.path}/SKILL.md";
        })
        skills.pstack)
      ++ lib.optionals cfg.mattpocock.enable (map (s: {
          name = "${s.name}/SKILL.md";
          path = "${s.path}/SKILL.md";
        })
        skills.mattpocock)
      ++ [
        {
          name = "status/SKILL.md";
          path = "${skills.status.path}/SKILL.md";
        }
      ]
      ++ lib.optional cfg.mtg-commander.enable {
        name = "mtg-commander/SKILL.md";
        path = skills.mtg-commander.path;
      }
      # The upstream SKILL.md is a discovery stub telling the agent to run
      # `agent-browser skills get core`, so the version-matched content comes
      # from the binary at runtime rather than from the store.
      ++ lib.optional cfg.agent-browser.enable {
        name = "agent-browser/SKILL.md";
        path = "${skills.agent-browser}/share/agent-browser/skills/agent-browser/SKILL.md";
      };

    skillsDir = pkgs.linkFarm "omp-skills" skillEntries;

    # A config *overlay*, not ~/.omp/agent/config.yml. omp loads PI_CONFIG_FILES
    # after the global config and lets it win, which is exactly what a wrapper
    # wants: these keys stay authoritative while config.yml — the file `/settings`
    # and the onboarding wizard write to — stays a mutable file omp owns.
    # Declaring them through the upstream module's `settings` option instead
    # would copy over config.yml on every switch and silently revert every
    # in-app settings change.
    configOverlay = (pkgs.formats.yaml {}).generate "omp-overlay.yml" {
      modelRoles.default = "anthropic/${pool.defaultModel}";

      skills.customDirectories = ["${skillsDir}"];

      # Nix owns the binary; the update check can only ever offer to write into
      # the read-only store.
      startup.checkUpdate = false;
    };

    # hiPrio to win over the plain binary `programs.omp` installs. Tolerant of a
    # missing render: a host whose opnix secrets haven't landed yet should still
    # get a usable TUI (and a pointer at why it can't reach the pool) rather than
    # an `omp` that refuses to launch. The values are read rather than sourced —
    # they're data, not shell.
    ompWrapper = lib.hiPrio (pkgs.writeShellScriptBin "omp" ''
      export PI_CONFIG_FILES=${configOverlay}

      # Never present a nested `claude` session's local pool token upstream.
      unset ANTHROPIC_AUTH_TOKEN

      if [ -r ${pool.urlFile} ] && [ -r ${pool.apiKeyFile} ]; then
        ANTHROPIC_BASE_URL=$(< ${pool.urlFile})
        ANTHROPIC_API_KEY=$(< ${pool.apiKeyFile})
        export ANTHROPIC_BASE_URL ANTHROPIC_API_KEY
      else
        echo "omp: cannot read ${pool.urlFile} / ${pool.apiKeyFile} —" >&2
        echo "     the work pool is not configured here. myNixOS.opnix-secrets.enable" >&2
        echo "     must be on, and you must be in the onepassword-secrets group" >&2
        echo "     (re-login after the first deploy)." >&2
      fi

      exec ${lib.getExe config.programs.omp.package} "$@"
    '');

    # omp generates its completions from live command/flag metadata, so they
    # can't drift from the CLI. Upstream suggests eval-ing that from .zshrc, but
    # the generator is a Bun process that measures at ~0.67s a run — paying that
    # on every shell start is absurd, so bake it at build time instead. Home
    # Manager already puts each profile's share/zsh/site-functions on fpath.
    zshCompletions = pkgs.runCommand "omp-zsh-completions" {} ''
      mkdir -p $out/share/zsh/site-functions
      HOME=$TMPDIR ${lib.getExe config.programs.omp.package} completions zsh \
        > $out/share/zsh/site-functions/_omp
      head -1 $out/share/zsh/site-functions/_omp | grep -q '^#compdef omp$'
    '';
  in {
    imports = [inputs.omp.homeManagerModules.default];

    options.myHomeManager.omp = {
      enable = lib.mkEnableOption "myHomeManager.omp";
      agent-browser.enable =
        lib.mkEnableOption "Vercel agent-browser CLI + omp skill"
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
      programs.omp.enable = true;

      home.packages =
        [ompWrapper]
        ++ lib.optionals config.programs.zsh.enable [zshCompletions]
        ++ lib.optional cfg.mtg-commander.enable skills.scryfall
        ++ lib.optional cfg.agent-browser.enable skills.agent-browser;

      # omp's native user-level context file, which outranks — and therefore
      # shadows — every other provider's (~/.claude/CLAUDE.md included). Same
      # source Claude Code, opencode and pi get, so the agents can't disagree
      # about what this machine is.
      home.file.".omp/agent/AGENTS.md".source = ./global-agent-instructions.md;
    };
  };
}
