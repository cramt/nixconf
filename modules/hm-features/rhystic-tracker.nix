{...}: {
  hmModules.features.rhystic-tracker = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.rhystic-tracker;
  in {
    options.myHomeManager.rhystic-tracker = {
      enable = lib.mkEnableOption "myHomeManager.rhystic-tracker";
      service.enable = lib.mkEnableOption "start the tracker in the tray at login so it tails Player.log unattended";
    };

    config = lib.mkIf cfg.enable {
      home.packages = [pkgs.rhystic-tracker];

      # Needs the graphical session for its tray icon and webview, so this is a
      # login service rather than a boot one. --hidden is a nixconf patch; see
      # packages/rhystic-tracker/default.nix.
      systemd.user.services.rhystic-tracker = lib.mkIf cfg.service.enable {
        Unit = {
          Description = "Rhystic Tracker MTG Arena log tailer";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${lib.getExe pkgs.rhystic-tracker} --hidden";
          Restart = "on-failure";
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
  };
}
