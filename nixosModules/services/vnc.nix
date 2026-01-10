{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.services.vnc;
in {
  options.myNixOS.services.vnc = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "cramt";
      description = "User to run the VNC server as";
    };
    display = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "VNC display number (port will be 5900 + display)";
    };
    geometry = lib.mkOption {
      type = lib.types.str;
      default = "1920x1080";
      description = "Screen resolution for VNC session";
    };
    depth = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "Color depth for VNC session";
    };
    localhost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only allow connections from localhost (use SSH tunneling)";
    };
  };

  config = let
    port = 5900 + cfg.display;
    localhostFlag =
      if cfg.localhost
      then "yes"
      else "no";
  in {
    environment.systemPackages = [pkgs.tigervnc];

    # Minimal X11/Xfce for VNC access
    services.xserver = {
      enable = true;
      desktopManager.xfce.enable = true;
    };

    services.displayManager = {
      defaultSession = "xfce";
    };

    # TigerVNC server systemd service
    systemd.services.tigervnc = {
      description = "TigerVNC Server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /home/${cfg.user}/.vnc";
        ExecStart = "${pkgs.tigervnc}/bin/vncserver :${toString cfg.display} -geometry ${cfg.geometry} -depth ${toString cfg.depth} -fg -localhost ${localhostFlag} -SecurityTypes None";
        ExecStop = "${pkgs.tigervnc}/bin/vncserver -kill :${toString cfg.display}";
        Restart = "on-failure";
      };
    };

    # Open VNC port
    networking.firewall.allowedTCPPorts = lib.mkIf (!cfg.localhost) [port];
  };
}
