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
      rotate = 270;
      tooltip-format = "{:%A %B %d %Y | %H:%M}";
      format = " {:%d/%m/%Y  %H:%M:%S}";
      interval = 1;
    };

    cpu = {
      format = "﬙ {usage}%";
      on-click = "alacritty -e btop";
    };

    memory = {
      format = " {}%";
      on-click = "alacritty -e btop";
    };

    backlight = {
      format = "{icon} {percent}%";
      format-icons = ["" ""];
      on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl -c backlight set 1%-";
      on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl -c backlight set +1%";
    };

    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon} {capacity}%";
      format-icons = ["" "" "" "" ""];
    };

    network = {
      rotate = 270;
      format = "⚠ Disabled";
      format-wifi = " {ipaddr}";
      format-ethernet = " {ipaddr}";
      format-disconnected = "⚠ Disconnected";
    };

    pulseaudio = {
      scroll-step = 1;
      format-source = "";
      format-source-muted = "";
      format = "{icon} {volume}% {format_source}";
      format-muted = "muted  {format_source}";
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
