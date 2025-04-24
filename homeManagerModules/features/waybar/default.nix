{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myHomeManager.waybar;
  mainWaybarConfig = {
    layer = "top";
    position = "right";
    output = cfg.monitors;
    width = 15;
    spacing = 8;

    modules-left = [
      "sway/workspaces"
      "sway/mode"
      "sway/window"
      "sway/scratchpad"
    ];
    modules-right = [
      "power-profiles-daemon"
      "idle_inhibitor"
      "backlight"
      "cpu"
      "memory"
      "sway/language"
      "battery"
      "network"
      "pulseaudio"
      "tray"
      "clock"
      "custom/power"
    ];

    "sway/workspaces" = {
      format = "{icon}";
      format-icons = {
        "1" = "1";
        "2" = "2";
        "3" = "3";
        "4" = "4";
        "5" = "5";
        "6" = "6";
        "7" = "7";
        "8" = "8";
        "9" = "9";
        "10" = "10";
      };
      disable-scroll = true;
      all-outputs = true;
      on-click = "activate";
    };

    "sway/window" = {
      rotate = 270;
    };

    "sway/mode" = {
      rotate = 270;
      format = "<span style=\"italic\">{}</span>";
    };

    "sway/scratchpad" = {
      "format" = "{icon} {count}";
      "show-empty" = false;
      "format-icons" = ["" ""];
      "tooltip" = true;
      "tooltip-format" = "{app}: {title}";
    };

    idle_inhibitor = {
      format = "{icon}";
      format-icons = {
        activated = "";
        deactivated = "";
      };
    };

    tray = {
      spacing = 10;
    };

    clock = {
      tooltip-format = "{:%A %B %d %Y | %H:%M:%S}";
      format = "\n{:%d\n%m\n%y\n\n%H\n%M}";
      interval = 1;
    };

    cpu = {
      format = "﬙\n{usage}%";
      on-click = "alacritty -e btop";
    };

    memory = {
      format = "\n{}%";
      on-click = "alacritty -e btop";
    };

    backlight = {
      format = "{icon}\n{percent}%";
      format-icons = ["" ""];
      on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl -c backlight set 1%-";
      on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl -c backlight set +1%";
    };

    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon}\n{capacity}%";
      format-icons = ["" "" "" "" ""];
    };

    network = {
      tooltip-format = "{ipaddr}";
      format = "⚠ ";
      format-wifi = " ";
      format-ethernet = " ";
      format-disconnected = "⛔";
    };

    pulseaudio = {
      scroll-step = 1;
      format-source = "";
      format-source-muted = "";
      format = "{icon}\n{format_source}\n{volume}%";
      format-muted = "\n{format_source}";
      format-icons = {
        headphones = "";
        handsfree = "";
        headset = "";
        phone = "";
        portable = "";
        car = "";
        default = ["" ""];
      };
      on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
    };

    "custom/power" = {
      format = "⏻";
      on-click = "rofi -show powermenu";
      tooltip = false;
    };
  };
in {
  options.myHomeManager.waybar = {
    monitors = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = ''
        specific monitors to put the bar on
      '';
    };
  };
  config = {
    stylix.targets.waybar = {
      enableLeftBackColors = false;
      enableRightBackColors = true;
    };
    programs.waybar = {
      enable = true;
      settings = {mainBar = mainWaybarConfig;};
    };
  };
}
