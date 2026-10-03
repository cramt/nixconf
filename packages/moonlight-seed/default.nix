# Writes a pre-generated pairing into Moonlight.conf through Qt's own
# QSettings (see main.cpp for why it isn't a script). QtCore only, built
# against the qtbase moonlight-qt links, so it adds next to nothing to a
# closure that already has Moonlight.
{
  stdenv,
  pkg-config,
  qt6,
}:
stdenv.mkDerivation {
  pname = "moonlight-seed";
  version = "1";
  src = ./main.cpp;
  dontUnpack = true;

  nativeBuildInputs = [pkg-config];
  buildInputs = [qt6.qtbase];
  # A CLI on QtCore alone: no platform plugins to find.
  dontWrapQtApps = true;

  buildPhase = ''
    runHook preBuild
    $CXX -std=c++17 -O2 -Wall -Wextra -fPIC $src \
      $(pkg-config --cflags --libs Qt6Core) -o moonlight-seed
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 moonlight-seed $out/bin/moonlight-seed
    runHook postInstall
  '';

  meta.mainProgram = "moonlight-seed";
}
