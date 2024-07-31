{ pkgs, ... }:
{
  home.packages = with pkgs; [
    wowup-cf
  ];
}
