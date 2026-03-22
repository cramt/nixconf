{ inputs, ... }: {
  hmModules.features.openclaw = { config, lib, pkgs, ... }: {
    imports = [
      inputs.nix-openclaw.homeManagerModules.openclaw
    ];
    options.myHomeManager.openclaw.enable = lib.mkEnableOption "myHomeManager.openclaw";
    config = lib.mkIf config.myHomeManager.openclaw.enable {
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
    };
  };
}
