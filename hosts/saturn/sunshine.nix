# saturn's side of Moonlight: the Steam games it offers (games.nix), and the
# ultrawide dropping to 16:9 for as long as a stream runs.
{
  config,
  lib,
  pkgs,
  ...
}: let
  output = (builtins.head (import ./monitors.nix)).port;
  # The ultrawide's only 16:9 mode at 1440 lines.
  stream = {
    width = 2560;
    height = 1440;
    refresh = "119.998";
  };

  # KMS capture sends the scanout as-is, so at 5120x1440 the TV got a 32:9
  # strip letterboxed into 16:9, the game a window somewhere in the middle of
  # it. Nobody's at the desk mid-stream, so a pillarboxed monitor costs
  # nothing. The mode in use beforehand is saved on `do` and put back on
  # `undo`, in whichever session is running: COSMIC day to day, niri now and
  # then.
  display = pkgs.writeShellApplication {
    name = "sunshine-stream-display";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.cosmic-randr config.programs.niri.package];
    text = ''
      saved="''${XDG_RUNTIME_DIR:?}/sunshine-display-mode"

      if niri msg version >/dev/null 2>&1; then
        current() {
          niri msg --json outputs |
            jq -r --arg o ${output} '.[$o] | .modes[.current_mode] | "\(.width)x\(.height)@\(.refresh_rate / 1000)"'
        }
        set_mode() { niri msg output ${output} mode "$1"; }
      else
        # `mode <w> <h> <mHz> current=#true` in cosmic-randr's KDL listing.
        current() {
          cosmic-randr list --kdl |
            grep -E '^\s*mode [0-9]+ [0-9]+ [0-9]+ current=#true' |
            head -n 1 |
            { read -r _ w h r _; echo "''${w}x''${h}@$((r / 1000)).$(printf '%03d' $((r % 1000)))"; }
        }
        # COSMIC now and then answers a mode change with "configuration
        # cancelled" (seen once in a row of them working), and a failed
        # prep-cmd keeps the stream from starting at all.
        set_mode() {
          local w=''${1%%x*} rest=''${1#*x}
          local args=(mode ${output} "$w" "''${rest%@*}" --refresh "''${rest#*@}")
          cosmic-randr "''${args[@]}" || { sleep 1; cosmic-randr "''${args[@]}"; }
        }
      fi

      case "$1" in
        do)
          # A second stream starting before undo ran mustn't save 16:9 as
          # the mode to go back to.
          [[ -s $saved ]] || current > "$saved"
          set_mode ${toString stream.width}x${toString stream.height}@${stream.refresh}
          ;;
        undo)
          [[ -s $saved ]] || exit 0
          set_mode "$(< "$saved")"
          rm -f "$saved"
          ;;
      esac
    '';
  };

  # Borderless fullscreen at the stream's size, or a game comes back up in
  # whatever window it was last closed in.
  fullscreenArgs.unity = [
    "-window-mode"
    "borderless"
    "-screen-fullscreen"
    "1"
    "-screen-width"
    (toString stream.width)
    "-screen-height"
    (toString stream.height)
  ];

  # `steam-game <appid> [args...]`: launches the game and lives exactly as
  # long as it does, so Sunshine can track it as the app's process. Stopping
  # the app from Moonlight (going Home on ganymede) ends the game, and
  # quitting the game ends the stream; a `detached` launch did neither.
  #
  # Steam hands the launch to its running instance and returns at once, so
  # the game is found by the reaper Steam runs every game under. Only the
  # game's: Steam first runs the install scripts under a reaper of their own,
  # `AppId=<id> Install=1 --`, which exits seconds before the game starts and
  # ended the stream with it.
  #
  # The launch goes through systemd-run, not as Sunshine's child: Sunshine's
  # capability wrapper (capSysAdmin, for KMS capture) leaves CAP_SYS_ADMIN
  # inheritable, and Steam's bwrap refuses to start with unexpected
  # capabilities, so the launch died silently and Moonlight just showed the
  # desktop. https://github.com/containers/bubblewrap/issues/380 — drop
  # systemd-run once Sunshine stops passing the capability to its children.
  steamGame = pkgs.writeShellApplication {
    name = "steam-game";
    runtimeInputs = [pkgs.coreutils pkgs.procps pkgs.systemd];
    text = ''
      app=$1
      shift
      reaper="SteamLaunch AppId=$app -- "

      tree() {
        local pid
        for pid in "$@"; do
          echo "$pid"
          # shellcheck disable=SC2046
          tree $(pgrep -P "$pid" || true)
        done
      }
      stop() {
        # shellcheck disable=SC2046
        kill -TERM $(tree $(pgrep -f "$reaper")) 2>/dev/null || true
        exit 0
      }
      trap stop TERM INT

      systemd-run --user --collect --quiet ${lib.getExe config.programs.steam.package} -applaunch "$app" "$@"

      # Long enough for Steam to finish an update first.
      for _ in $(seq 600); do
        pgrep -f "$reaper" >/dev/null && break
        sleep 1 &
        wait $!
      done
      pgrep -f "$reaper" >/dev/null || { echo "app $app never started" >&2; exit 1; }

      while pgrep -f "$reaper" >/dev/null; do
        sleep 2 &
        wait $!
      done
    '';
  };
in {
  myNixOS.sunshine.apps = map (game: {
    inherit (game) name;
    cmd = lib.escapeShellArgs ([(lib.getExe steamGame) (toString game.steamAppId)] ++ fullscreenArgs.${game.engine});
    # Sunshine only takes .png box art.
    image-path = "${pkgs.runCommand "steam-${toString game.steamAppId}.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
      magick ${pkgs.fetchurl {
        url = "https://cdn.cloudflare.steamstatic.com/steam/apps/${toString game.steamAppId}/library_600x900.jpg";
        hash = game.artHash;
      }} $out
    ''}";
  }) (import ./games.nix);

  # Global, so Desktop gets it too.
  services.sunshine.settings.global_prep_cmd = builtins.toJSON [
    {
      do = "${lib.getExe display} do";
      undo = "${lib.getExe display} undo";
    }
  ];
}
