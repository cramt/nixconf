{ pkgs, ... }: {
  home.packages = with pkgs; [
    slack
    postgresql
    teams-for-linux
    ngrok
  ];
}
