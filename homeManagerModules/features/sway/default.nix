{ lib, config, pkgs, ... }:

let
  cfg = config.myHomeManager.sway;
  mod = "Mod4";
  backgroundAsset = ./../../../media/cosmere.mp4;
  screenSpecificVideos = builtins.mapAttrs
    (
      name: value:
        let
          res = "${toString value.res.width}:${toString value.res.height}";
        in
        (pkgs.runCommand "screen_specific_videos" { } ''
          mkdir -p $out

          ${pkgs.ffmpeg}/bin/ffmpeg -i ${backgroundAsset} -filter:v "scale=${res}:force_original_aspect_ratio=increase,crop=${res}" $out/output.mp4
        '')

    )
    cfg.monitors;
  setBackground = pkgs.writeShellScriptBin "set_background" ''
    pkill mpvpaper 
    ${lib.strings.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (
      name: value: "${pkgs.mpvpaper}/bin/mpvpaper -o \"--loop\" -f '${name}' ${value}/output.mp4"
    ) screenSpecificVideos)}
    sleep 1
    pkill swaybg #stylix sets the wallpapir like a dumbdumb
  '';
  lockCommand = "${pkgs.swaylock}/bin/swaylock";
  rofiMonitor = pkgs.writeShellScriptBin "rofi_monitor" ''
    monitor="$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq '[.[].focused] | index(true)')"
    rofi $@
  '';
  rofiGeneric = pkgs.writeShellScriptBin "rofi_generic" ''
    ${rofiMonitor}/bin/rofi_monitor -show $(echo "calc,emoji,powermenu,top" | rofi -sep ',' -dmenu)
  '';
  rofiCommand = "${rofiMonitor}/bin/rofi_monitor -show drun";
  rofiGenericCommand = "${rofiGeneric}/bin/rofi_generic";
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
            name: value: ((builtins.removeAttrs value [ "workspace" ]) // {
              res = "${toString value.res.width}x${toString value.res.height}";
            })
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
        menu = rofiCommand;
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
            "${mod}+shift+d" = "exec ${rofiGenericCommand}";
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

    myHomeManager.rofi.enable = true;
    myHomeManager.waybar.enable = true;
    home.packages = with pkgs; [
      sway-easyfocus
      sway-contrib.grimshot
      wl-clipboard
      eww
      networkmanagerapplet
    ];
  };
}
