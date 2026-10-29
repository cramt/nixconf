# Dictation into whatever window has focus: press Super+Shift+D, talk, press it
# again, and voxtype types the transcript. Transcription happens on luna's GPU
# (modules/services/whisper.nix); this side only records and types.
#
# The hotkey is a compositor binding running `voxtype record toggle`, not
# voxtype's own evdev listener: that one needs the user in `input`, which can
# read every keyboard on the box. The cost is toggle instead of push-to-talk,
# since neither COSMIC nor niri can bind key release.
#
# The whisper prompt is set server-side, so it's deliberately not sent from
# here: a request's own prompt would replace the vocabulary.
{...}: {
  hmModules.features.dictation = {
    config,
    lib,
    pkgs,
    ...
  }: let
    dictation = import ../../myLib/dictation.nix;
    toggle = "${lib.getExe pkgs.voxtype} record toggle";
    settings = {
      state_file = "auto";
      hotkey.enabled = false;
      audio = {
        device = "default";
        sample_rate = 16000;
        max_duration_secs = 120;
        feedback = {
          enabled = true;
          theme = "subtle";
        };
      };
      whisper = {
        mode = "remote";
        remote_endpoint = "http://${dictation.host}:${toString dictation.port}";
        language = "en";
        remote_timeout_secs = 30;
      };
      output = {
        mode = "type";
        fallback_to_clipboard = true;
        notification.on_transcription = false;
      };
      text.replacements = dictation.replacements;
    };
  in {
    options.myHomeManager.dictation.enable = lib.mkEnableOption "myHomeManager.dictation";

    config = lib.mkIf config.myHomeManager.dictation.enable {
      home.packages = [pkgs.voxtype];
      wayland.desktopManager.cosmic.shortcuts = lib.mkIf config.myHomeManager.cosmic.enable [
        {
          key = "Super+Shift+d";
          action = config.lib.cosmic.mkRON "enum" {
            variant = "Spawn";
            value = [toggle];
          };
        }
      ];
      programs.niri.settings.binds = lib.mkIf config.myHomeManager.niri.enable {
        "Mod+Shift+D".action.spawn = ["${lib.getExe pkgs.voxtype}" "record" "toggle"];
      };

      xdg.configFile."voxtype/config.toml".source = (pkgs.formats.toml {}).generate "voxtype.toml" settings;

      systemd.user.services.voxtype = {
        Unit = {
          Description = "voxtype push-to-talk dictation";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
          X-Restart-Triggers = [config.xdg.configFile."voxtype/config.toml".source];
        };
        Service = {
          ExecStart = "${lib.getExe pkgs.voxtype} daemon";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
  };
}
