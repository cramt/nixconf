{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.myHomeManager.sway;
  mod = "Mod4";
  screenSpecificVideos =
    builtins.mapAttrs
    (
      name: value: let
        res = "${toString value.res.width}:${toString value.res.height}";
        rotation = lib.concatMapStrings (_: ",transpose=2") (lib.range 1 (value.transform / 90));
      in (pkgs.runCommand "screen_specific_videos" {} ''
        mkdir -p $out

        ${pkgs.ffmpeg}/bin/ffmpeg -i ${cfg.backgroundVideo} -filter:v "scale=${res}:force_original_aspect_ratio=increase,crop=${res}${rotation}" $out/output.mp4
      '')
    )
    cfg.monitors;
  killVesktop = (import ../../../scripts/kill_vesktop.nix) {
    inherit pkgs;
  };
  setBackground = pkgs.writeShellScriptBin "set_background" ''
    pkill mpvpaper
    ${lib.strings.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (
        name: value: "${pkgs.mpvpaper}/bin/mpvpaper -o \"--loop\" -f '${name}' ${value}/output.mp4"
      )
      screenSpecificVideos)}
    sleep 1
    pkill swaybg #stylix sets the wallpapir like a dumbdumb
  '';
  mkRunIfNoMedia = name: cmd: "${pkgs.writeShellScriptBin name ''
    if [[ "$(${pkgs.playerctl}/bin/playerctl status)" != "Playing" ]]; then
      ${killVesktop}/bin/kill_vesktop
      ${cmd}
    fi
  ''}/bin/${name}";
  lockCommand = "${pkgs.swaylock}/bin/swaylock -f";
  swayrCommand = "${pkgs.swayr}/bin/swayr";
  execSwayr = "exec ${swayrCommand}";
in {
  options.myHomeManager.sway = {
    monitors = lib.mkOption {
      default = {};
      description = ''
        sway monitor setup
      '';
    };
    backgroundVideo = lib.mkOption {
      type = lib.types.path;
    };
  };
  config = {
    stylix.targets.hyprpaper.enable = false;
    stylix.targets.hyprland.enable = false;
    services.playerctld.enable = true;
    home.sessionVariables = {
      WLR_RENDERER = "vulkan";
      WLR_NO_HARDWARE_CURSORS = "1";
      XWAYLAND_NO_GLAMOR = "1";
    };
    programs.tofi = {
      enable = true;
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
          timeout = 60 * 15;
          command = mkRunIfNoMedia "hypernate" "${pkgs.systemd}/bin/systemctl suspend";
        }
        {
          timeout = 60 * 10;
          command = mkRunIfNoMedia "lock" lockCommand;
        }
        {
          timeout = 60 * 5;
          command = mkRunIfNoMedia "screen_off" ''${pkgs.sway}/bin/swaymsg "output * dpms off"'';
          resumeCommand = ''${pkgs.sway}/bin/swaymsg "output * dpms on"'';
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
      config = {
        output =
          builtins.mapAttrs
          (
            name: value: ((builtins.removeAttrs value ["workspace"])
              // {
                res = "${toString value.res.width}x${toString value.res.height}";
                transform = toString value.transform;
              })
          )
          cfg.monitors;
        workspaceOutputAssign =
          builtins.attrValues
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
        terminal = "rio";
        menu = "${pkgs.tofi}/bin/tofi-drun | xargs swaymsg exec --";
        defaultWorkspace = "1";
        window = {
          border = 2;
          titlebar = false;
        };
        floating = {
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
          {
            command = "${pkgs.autotiling}/bin/autotiling";
            always = true;
          }
        ];
        modes = {
          resize = let
            size = builtins.toString 10;
            unit = "ppt";
          in rec {
            Down = "resize shrink height ${size} ${unit}";
            j = Down;
            Up = "resize grow height ${size} ${unit}";
            k = Up;
            Left = "resize grow width ${size} ${unit}";
            h = Left;
            Right = "resize shrink width ${size} ${unit}";
            l = Right;
            Return = "mode default";
            Escape = Return;
          };
        };
        keybindings =
          lib.mkOptionDefault
          {
            "print" = "exec grimshot --notify copy area";
            "${mod}+q" = "kill";
            "${mod}+shift+d" = "exec ${inputs.sherlock.packages.${pkgs.system}.default}/bin/sherlock";
            "${mod}+x" = "exec ${pkgs.sway-easyfocus}/bin/sway-easyfocus";
            "${mod}+z" = "exec ${pkgs.alsa-utils}/bin/amixer set Capture toggle";
            "${mod}+f1" = "exec ${lockCommand}";
            "${mod}+tab" = "${execSwayr} switch-to-urgent-or-lru-window";
            "${mod}+Shift+Return" = "exec --no-startup-id ${pkgs.playerctl}/bin/playerctl play-pause";
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
    myHomeManager.sherlock.enable = true;
    home.packages = with pkgs; [
      sway-easyfocus
      sway-contrib.grimshot
      wl-clipboard
      eww
      networkmanagerapplet
    ];
  };
}
