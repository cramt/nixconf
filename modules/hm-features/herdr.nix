{ inputs, ... }: {
  hmModules.features.herdr = { config, lib, pkgs, ... }:
  let
    cfg = config.myHomeManager.herdr;
    herdrPkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in {
    options.myHomeManager.herdr = {
      enable = lib.mkEnableOption "myHomeManager.herdr";
      integrations = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "claude" "codex" "pi" ];
        example = [ "claude" ];
        description = ''
          Agent integrations to (re)install on every activation via
          `herdr integration install <name>`. Each drops a state-reporting hook
          (e.g. ~/.claude/hooks/herdr-agent-state.sh) and registers it with the
          agent so herdr can show working/blocked/idle/done per pane.

          The hook scripts are version-stamped and "managed by herdr" — herdr
          overwrites them when the integration version changes, so reinstalling
          on activation keeps them in lockstep with the installed herdr version
          (which is why this is an install command, not a pinned home.file).

          NOTE on codex: its ~/.codex/config.toml is a read-only home-manager
          symlink, so herdr cannot set `[features] hooks = true` there and that
          one step errors (harmlessly — the hook + hooks.json are still written).
          The flag is set declaratively in modules/hm-features/codex.nix instead.
        '';
      };
    };
    config = lib.mkIf cfg.enable {
      home.packages = [ herdrPkg ];

      # Idempotent: `integration install` "ensures" each file, so re-running on
      # every switch is safe. Runs after writeBoundary so the agents' own config
      # (incl. codex's read-only config.toml symlink) is already in place.
      home.activation.herdrIntegrations =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # pi writes its hook into the extensions dir and refuses if it's absent.
          run mkdir -p "$HOME/.pi/agent/extensions"
          ${lib.concatMapStringsSep "\n" (name: ''
            # `|| true`: best-effort per agent — e.g. codex's read-only config.toml
            # makes the final config write fail after the hook is already installed.
            run ${herdrPkg}/bin/herdr integration install ${lib.escapeShellArg name} \
              || true
          '') cfg.integrations}
        '';
    };
  };
}
