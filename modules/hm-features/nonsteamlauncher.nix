{ inputs, ... }: {
  hmModules.features.nonsteamlauncher = { config, lib, pkgs, ... }: let
    env =
      (pkgs.steam-fhsenv-without-steam.override {
        extraPkgs = pkgs: [
          pkgs.zenity pkgs.wget pkgs.curl pkgs.python314 pkgs.busybox pkgs.sudo
          inputs.NonSteamLaunchers
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
            ${lib.getExe env} ${inputs.NonSteamLaunchers}/NonSteamLaunchers.sh
          '')
      ];
    };
  };
}
