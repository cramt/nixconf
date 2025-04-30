{pkgs, ...}: {
  myHomeManager = {
    distrobox.enable = true;
  };
  home.packages = with pkgs; [
    slack
    postgresql
    teams-for-linux
    ngrok
  ];
}
