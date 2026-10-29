# Push-to-talk dictation into whatever window has focus: hold Right Ctrl, talk,
# release, and voxtype types the transcript. Transcription happens on luna's GPU
# (modules/services/whisper.nix); this side only records and types.
#
# The hotkey is voxtype's own evdev listener rather than a compositor binding,
# because COSMIC can't bind key release and push-to-talk needs it. That works
# because enabling this puts the user in the `input` group (bundles/nixos-users.nix).
# Right Ctrl because Right Alt is AltGr on the Danish layout.
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
    settings = {
      state_file = "auto";
      hotkey = {
        enabled = true;
        key = "RIGHTCTRL";
        mode = "push_to_talk";
      };
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
