{ pkgs, ... }:
let
  mainWaybarConfig = {
    layer = "top";
    position = "top";
    height = 30;
    spacing = 4;

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
      "keyboard-state"
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

    "sway/mode" = {
      format = "<span style=\"italic\">{}</span>";
    };

    "sway/scratchpad" = {
      "format" = "{icon} {count}";
      "show-empty" = false;
      "format-icons" = [ "" "" ];
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
      tooltip-format = "{:%A %B %d %Y | %H:%M}";
      format-alt = " {:%a %d %b  %I:%M %p}";
      format = " {:%d/%m/%Y  %H:%M:%S}";
      interval = 1;
    };

    cpu = {
      format = "﬙ {usage}%";
      on-click = "alacritty -e htop";
    };

    memory = {
      format = " {}%";
      on-click = "alacritty -e htop";
    };

    backlight = {
      format = "{icon} {percent}%";
      format-icons = [ "" "" ];
      on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl -c backlight set 1%-";
      on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl -c backlight set +1%";
    };

    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon} {capacity}%";
      format-icons = [ "" "" "" "" "" ];
    };

    network = {
      format = "⚠ Disabled";
      format-wifi = " {essid}";
      format-ethernet = " {ifname}: {ipaddr}/{cidr}";
      format-disconnected = "⚠ Disconnected";
      on-click = "nm-connection-editor";
    };

    pulseaudio = {
      scroll-step = 1;
      format = "{icon} {volume}%";
      format-bluetooth = "{icon} {volume}%";
      format-muted = "muted ";
      format-icons = {
        headphones = "";
        handsfree = "";
        headset = "";
        phone = "";
        portable = "";
        car = "";
        default = [ "" "" ];
      };
      on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
    };

    "custom/power" = {
      format = "⏻";
      on-click = "rofi -show powermenu";
      tooltip = false;
    };
  };
in
{
  config = {
    stylix.targets.waybar = {
      enableLeftBackColors = false;
      enableRightBackColors = true;
    };
    programs.waybar = {
      enable = true;
      settings = { mainBar = mainWaybarConfig; };
    };
  };
}
