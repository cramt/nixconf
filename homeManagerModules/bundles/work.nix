{ pkgs, ... }: {
  home.packages = with pkgs; [
    slack
    vagrant
    postgresql
  ];
}
