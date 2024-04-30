{ pkgs, ... }: {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    #    package = pkgs.steam.overrideAttrs
    #      (e: {
    #        postInstall = ''
    #          ${e.postInstall}
    #          sed -e 's,Exec=steam,Exec=steam -silent,g' $out/share/applications/steam.desktop > $out/share/applications/steam.desktop
    #        '';
    #      });
  };
}
