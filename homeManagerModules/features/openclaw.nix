{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  programs.openclaw = {
    enable = true;

    bundledPlugins = {
      summarize.enable = true;
      peekaboo.enable = false;
      poltergeist.enable = false;
      sag.enable = false;
      camsnap.enable = false;
      gogcli.enable = false;
      goplaces.enable = true;
      bird.enable = false;
      sonoscli.enable = false;
      imsg.enable = false;
    };
  };
}
