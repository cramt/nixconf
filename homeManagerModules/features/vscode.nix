{pkgs, ...}: {
  config = {
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
}
