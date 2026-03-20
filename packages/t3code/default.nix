{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
}:
let
  pname = "t3code";
  version = "0.0.13";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-oHKIh+aHsbGVHEoLLjItl6AbVRwvWVlZaIWyHKiekVc=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    # Desktop entry
    install -Dm444 ${appimageContents}/t3-code-desktop.desktop $out/share/applications/t3code.desktop
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=t3code'

    # Icon
    install -Dm444 ${appimageContents}/t3-code-desktop.png $out/share/icons/hicolor/512x512/apps/t3code.png

    # Also check for hicolor icons
    for size in 16 32 48 64 128 256 512 1024; do
      icon="${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/t3-code-desktop.png"
      if [ -f "$icon" ]; then
        install -Dm444 "$icon" "$out/share/icons/hicolor/''${size}x''${size}/apps/t3code.png"
      fi
    done
  '';

  meta = with lib; {
    description = "Minimal web GUI for coding agents with Claude Code support";
    homepage = "https://github.com/pingdotgg/t3code";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3code";
  };
}
