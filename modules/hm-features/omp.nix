{inputs, ...}: {
  hmModules.features.omp = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.omp;

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

    options.myHomeManager.omp.enable = lib.mkEnableOption "myHomeManager.omp";

    config = lib.mkIf cfg.enable {
      programs.omp.enable = true;

      home.packages = lib.optionals config.programs.zsh.enable [zshCompletions];

      # NB: `programs.omp.settings` is deliberately left unset. It renders
      # ~/.omp/agent/config.yml as a read-only store symlink, and that same file
      # is the canonical write target for `/settings`, `omp config set` and the
      # first-run provider setup — declaring it would make every in-app settings
      # change silently revert on the next switch. Provider auth (OAuth to
      # Claude/Copilot/ChatGPT) isn't expressible in Nix anyway, so config.yml
      # stays mutable and omp owns it.

      # No ~/.omp/agent/AGENTS.md here on purpose: omp's `claude` discovery
      # provider already loads ~/.claude/CLAUDE.md at user scope, so the global
      # instructions pi needs a copied file for (see pi.nix) arrive for free.
      # Writing the native AGENTS.md would *shadow* it — native outranks claude.
    };
  };
}
