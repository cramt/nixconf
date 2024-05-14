{ pkgs, ... }: {
  home.packages = with pkgs; [
    slack
    postgresql
  ];
}
