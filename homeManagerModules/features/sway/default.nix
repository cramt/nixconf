{ lib, config, pkgs, ... }:

let
  cfg = config.myHomeManager.sway;
  mod = "Mod4";
  lockCommand = "${pkgs.swaylock}/bin/swaylock";
  backgroundImage = ./../../../media/pattern.jpg;
  setBackground = pkgs.writeShellScriptBin "set_background" ''
    pkill swaybg
    swaybg -i ${backgroundImage} -m fit &
  '';
  swayrCommand = "${pkgs.swayr}/bin/swayr";
  execSwayr = "exec ${swayrCommand}";
in
{
  options.myHomeManager.sway = {
    monitors = lib.mkOption {
      default = { };
      description = ''
        sway monitor setup
      '';
    };
  };
  config = {
    home.sessionVariables = {
      WLR_RENDERER = "vulkan";
      WLR_NO_HARDWARE_CURSORS = "1";
      XWAYLAND_NO_GLAMOR = "1";
    };
    programs.swaylock = {
      enable = true;
      settings = {
        indicator-caps-lock = true;
        scaling = "fill";
        font = "Ubuntu Mono";
        font-size = 20;
        indicator-radius = 360;
      };
    };
    programs.swayr = {
      enable = true;
      systemd.enable = true;
    };
    services.swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 60 * 5;
          command = lockCommand;
        }
        {
          timeout = 60 * 10;
          command = "systemctl suspend";
        }
      ];
      events = [
        {
          event = "before-sleep";
          command = lockCommand;
        }
        {
          event = "lock";
          command = lockCommand;
        }
      ];
    };
    wayland.windowManager.sway = {
      enable = true;
      xwayland = true;
      extraConfig = ''
        workspace 1
      '';
      wrapperFeatures.gtk = true;
      extraOptions = [ "--unsupported-gpu" ];
      config = {
        output = builtins.mapAttrs
          (
            name: value: builtins.removeAttrs value [ "workspace" ]
          )
          cfg.monitors;
        workspaceOutputAssign = builtins.attrValues
          (
            builtins.mapAttrs
              (
                name: value: {
                  output = name;
                  workspace = value.workspace;
                }
              )
              cfg.monitors
          );
        modifier = mod;
        terminal = "alacritty";
        menu = "wofi --show drun";
        defaultWorkspace = "1";
        window = {
          border = 2;
          titlebar = false;
        };
        input = {
          "*" = {
            xkb_layout = "dk";
            xkb_variant = "nodeadkeys";
          };
        };
        startup = [
          {
            command = "${setBackground}/bin/set_background";
            always = true;
          }
        ];
        keybindings = lib.mkOptionDefault
          {
            "print" = "exec grimshot --notify copy area";
            "${mod}+q" = "kill";
            "${mod}+x" = "exec ${pkgs.sway-easyfocus}/bin/sway-easyfocus";
            "${mod}+f1" = "exec ${lockCommand}";
            "${mod}+tab" = "${execSwayr} switch-to-urgent-or-lru-window";
          };
        bars = [
          {
            command = "${pkgs.waybar}/bin/waybar";
          }
        ];
        gaps = {
          inner = 0;
          outer = 0;
          smartBorders = "on";
        };
      };
    };
    xdg.configFile."sway-easyfocus/config.yaml".source = ./easyfocus-config.yaml;

    myHomeManager.wofi.enable = lib.mkDefault
      true;
    myHomeManager.waybar.enable = lib.mkDefault
      true;
    home.packages = with pkgs; [
      sway-easyfocus
      sway-contrib.grimshot
      wl-clipboard
      eww
      networkmanagerapplet
      wofi
      waybar
      swaybg
    ];
  };
}
