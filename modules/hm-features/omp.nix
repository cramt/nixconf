{inputs, ...}: {
  hmModules.features.omp = {
    config,
    lib,
    ...
  }: let
    cfg = config.myHomeManager.omp;
  in {
    imports = [inputs.omp.homeManagerModules.default];

    options.myHomeManager.omp.enable = lib.mkEnableOption "myHomeManager.omp";

    config = lib.mkIf cfg.enable {
      programs.omp.enable = true;

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
