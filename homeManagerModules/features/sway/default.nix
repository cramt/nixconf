{ lib, config, pkgs, ... }:

let
  cfg = config.myHomeManager.sway;
  mod = "Mod4";
  lockCommand = "${pkgs.swaylock}/bin/swaylock";
  lockImage = ./../../../media/Abstract.jpg;
  backgroundImage = ./../../../media/pattern.jpg;
  setBackground = pkgs.writeShellScriptBin "set_background" ''
    pkill swaybg
    swaybg -i ${backgroundImage} -m fit &
  '';
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
        image = "${lockImage}";
        indicator-caps-lock = true;
        scaling = "fill";
        font = "Ubuntu Mono";
        font-size = 20;
        indicator-radius = 360;
        line-color = "#3b4252";
        text-color = "#d8dee9";
        inside-color = "#2e344098";
        inside-ver-color = "#5e81ac";
        line-ver-color = "#5e81ac";
        ring-ver-color = "#5e81ac98";
        ring-color = "#4c566a";
        key-hl-color = "#5e81ac";
        separator-color = "#4c566a";
        layout-text-color = "#eceff4";
        line-wrong-color = "#d08770";
      };
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
            "${mod}+f1" = "exec ${lockCommand}";
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
        colors = {
          background = "#f8f8f2";
          focused = {
            background = "#4d0426";
            border = "#4d0426";
            childBorder = "#4d0426";
            indicator = "#ff92df";
            text = "#f8f8f2";
          };
          focusedInactive = {
            background = "#44475A";
            border = "#44475A";
            childBorder = "#44475A";
            indicator = "#44475A";
            text = "#f8f8f2";
          };
          unfocused = {
            background = "#1d212a";
            border = "#44475A";
            childBorder = "#1d212a";
            indicator = "#1d212a";
            text = "#f8f8f2";
          };
          urgent = {
            background = "#f05c8e";
            border = "#44475A";
            childBorder = "#f05c8e";
            indicator = "#f05c8e";
            text = "#f8f8f2";
          };
          placeholder = {
            background = "#1d212a";
            border = "#1d212a";
            childBorder = "#1d212a";
            indicator = "#1d212a";
            text = "#f8f8f2";
          };
        };
      };
    };

    myHomeManager.wofi.enable = lib.mkDefault
      true;
    myHomeManager.waybar.enable = lib.mkDefault
      true;
    home.packages = with pkgs; [
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
