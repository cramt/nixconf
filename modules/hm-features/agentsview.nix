{...}: {
  hmModules.features.agentsview = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.agentsview;
  in {
    options.myHomeManager.agentsview = {
      enable = lib.mkEnableOption "myHomeManager.agentsview";
      service.enable = lib.mkEnableOption "run the agentsview server as a user service";
    };

    config = lib.mkIf cfg.enable {
      home.packages = [pkgs.agentsview];

      # Syncs agent sessions into ~/.agentsview and serves the dashboard
      # on 127.0.0.1:8080.
      systemd.user.services.agentsview = lib.mkIf cfg.service.enable {
        Unit.Description = "AgentsView session analytics server";
        Service = {
          ExecStart = "${lib.getExe pkgs.agentsview} serve --no-browser";
          Restart = "on-failure";
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
