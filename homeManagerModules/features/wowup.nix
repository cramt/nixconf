{ pkgs, lib, ... }:
let
  pname = "wowup";
  version = "2.11.0";
  name = "${pname}-${version}";

  src = pkgs.fetchurl {
    url = "https://github.com/WowUp/WowUp/releases/download/v${version}/WowUp-${version}.AppImage";
    sha256 = "Q1lrX87nQMu172D0QlCoFXbYr5WwXXUjPipL5tGn02k=";
  };

  appimageContents = pkgs.appimageTools.extractType2 { inherit name src; };

  wowup = pkgs.appimageTools.wrapType2
    rec {
      inherit name src;

      extraInstallCommands = ''
        mv $out/bin/${name} $out/bin/${pname}
        install -m 444 -D ${appimageContents}/*.desktop $out/share/applications/${pname}.desktop

        install -m 444 -D ${appimageContents}/${pname}.png $out/share/icons/hicolor/512x512/apps/${pname}.png

        substituteInPlace $out/share/applications/${pname}.desktop \
        	--replace 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U'
      '';

      meta = with lib; {
        description = "WowUp";
        homepage = "https://wowup.io/";
        license = licenses.gpl3;
        maintainers = [ ];
        platforms = [ "x86_64-linux" ];
      };
    };
in
{
  home.packages = [
    wowup
  ];
}
