{ ... }:
let
  mainWaybarConfig = {
    layer = "top";
    position = "top";
    height = 30;

    modules-left = [ "sway/workspaces" "sway/mode" "sway/window" ];
    modules-right = [ "backlight" "custom/keyboard-layout" "cpu" "memory" "battery" "network" "pulseaudio" "tray" "idle_inhibitor" "clock" "custom/power" ];

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

    "sway/window" = {
      format = "{}";
    };

    idle_inhibitor = {
      format = "{icon}";
      format-icons = {
        activated = "";
        deactivated = "";
      };
    };

    tray = {
      icon-size = 14;
      spacing = 5;
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
      on-scroll-down = "brightnessctl -c backlight set 1%-";
      on-scroll-up = "brightnessctl -c backlight set +1%";
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
      scroll-step = 5;
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
      on-click = "pavucontrol";
    };

    "custom/power" = {
      format = "⏻";
      on-click = "nwgbar";
      tooltip = false;
    };

    "custom/keyboard-layout" = {
      exec = "swaymsg -t get_inputs | grep -m1 'xkb_active_layout_name' | cut -d '\"' -f4";
      interval = 30;
      format = "  {}";
      signal = 1;
      tooltip = false;
    };
  };
in
{
  programs.waybar = {
    enable = true;
    settings = { mainBar = mainWaybarConfig; };
    style = builtins.readFile ./style.css;
  };
}
