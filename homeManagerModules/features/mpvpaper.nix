{
  pkgs,
  lib,
  config,
  ...
}: let
  backgroundVideo = config.myHomeManager.mpvpaper.backgroundVideo;
  monitors = config.myHomeManager.monitors;
  screenSpecificVideos =
    builtins.mapAttrs
    (
      name: value: let
        res = "${toString value.res.width}:${toString value.res.height}";
        rotation = lib.concatMapStrings (_: ",transpose=2") (lib.range 1 (value.transform / 90));
      in (pkgs.runCommand "screen_specific_videos" {} ''
        mkdir -p $out

        ${pkgs.ffmpeg}/bin/ffmpeg -i ${backgroundVideo} -filter:v "scale=${res}:force_original_aspect_ratio=increase,crop=${res}${rotation}" $out/output.mp4
      '')
    )
    monitors;
  setBackground = pkgs.writeShellScript "set_background" ''
    ${pkgs.busybox}/bin/pkill mpvpaper
    ${lib.strings.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (
        name: value: "${pkgs.mpvpaper}/bin/mpvpaper -o \"--loop\" -f '${name}' ${value}/output.mp4"
      )
      screenSpecificVideos)}
    ${pkgs.busybox}/bin/sleep 1
    ${pkgs.busybox}/bin/pkill swaybg
  '';
in {
  options.myHomeManager.mpvpaper = {
    backgroundVideo = lib.mkOption {
      type = lib.types.path;
    };
  };
  config = {
    systemd.user.services.mpvpaper = {
      Unit = {
        Description = "Start animated background on boot";
        After = ["graphical.target"];
      };
      Install = {
        WantedBy = ["default.target"];
      };
      Service = {
        ExecStart = setBackground;
        RemainAfterExit = false;
        Type = "oneshot";
      };
    };
  };
}
