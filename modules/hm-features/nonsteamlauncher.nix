{ ... }: {
  hmModules.features.nonsteamlauncher = { config, lib, pkgs, ... }: let
    nonSteamLaunchers = pkgs.npinsSources.NonSteamLaunchers;
    env =
      (pkgs.steam-fhsenv-without-steam.override {
        extraPkgs = pkgs: [
          pkgs.zenity pkgs.wget pkgs.curl pkgs.python314 pkgs.busybox pkgs.sudo
          nonSteamLaunchers
        ];
      })
      .run;
  in {
    options.myHomeManager.nonsteamlauncher.enable = lib.mkEnableOption "myHomeManager.nonsteamlauncher";
    config = lib.mkIf config.myHomeManager.nonsteamlauncher.enable {
      home.packages = [
        (pkgs.writeScriptBin
          "NonSteamLaunchers"
          ''
            mkdir -p ~/homebrew/plugins/
            touch ~/homebrew/plugins/_
            ${lib.getExe env} ${nonSteamLaunchers}/NonSteamLaunchers.sh
          '')
      ];
    };
  };
}
