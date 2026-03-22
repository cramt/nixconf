{ ... }: {
  hmModules.features.vscode = { config, lib, pkgs, ... }: {
    options.myHomeManager.vscode.enable = lib.mkEnableOption "myHomeManager.vscode";
    config = lib.mkIf config.myHomeManager.vscode.enable {
      stylix.targets.vscode.profileNames = ["cramt"];
      programs.vscode = {
        enable = true;
        profiles.cramt = {
          extensions = with pkgs.vscode-extensions; [
            github.vscode-pull-request-github
            github.vscode-github-actions
          ];
        };
      };
    };
  };
}
