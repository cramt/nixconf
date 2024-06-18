{ pkgs, ... }:
let
  sshLuna = pkgs.writeScriptBin "ssh_luna" "ssh cramt@192.168.0.103";
  sshLunaDesktop = pkgs.makeDesktopItem {
    name = "ssh-luna";
    desktopName = "ssh luna";
    exec = "${pkgs.alacritty}/bin/alacritty -e ${sshLuna}/bin/ssh_luna";
  };
in
{
  home.packages = [ sshLuna sshLunaDesktop ];
}
