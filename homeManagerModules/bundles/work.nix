{pkgs, ...}: {
  myHomeManager = {
    distrobox.enable = true;
  };
  home.packages = with pkgs; [
    scaleway-cli
    slack
    postgresql
    teams-for-linux
    ngrok
  ];
}
