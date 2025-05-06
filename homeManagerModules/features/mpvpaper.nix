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
in {
  options.myHomeManager.mpvpaper = {
    backgroundVideo = lib.mkOption {
      type = lib.types.path;
    };
  };
  config = {
    systemd.user.services =
      lib.mapAttrs' (name: value: {
        name = "mpvpaper_${builtins.hashString "md5" name}";
        value = {
          Unit = {
            Description = "Start animated background on boot";
            After = ["graphical.target"];
          };
          Install = {
            WantedBy = ["default.target"];
          };
          Service = {
            ExecStart = pkgs.writeShellScript "set_background" ''
              ${pkgs.mpvpaper}/bin/mpvpaper -o "--loop" "${name}" ${value}/output.mp4 || true
            '';
          };
        };
      })
      screenSpecificVideos;
  };
}
