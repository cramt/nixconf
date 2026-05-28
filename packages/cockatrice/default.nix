{
  lib,
  stdenv,
  qt6,
  cmake,
  protobuf,
  openssl,
  src,
}:
stdenv.mkDerivation {
  pname = "cockatrice";
  version = "3.0.1";

  inherit src;

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    qt6.qttools
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtmultimedia
    qt6.qtsvg
    qt6.qtwebsockets
    qt6.qtimageformats
    protobuf
    openssl
  ];

  meta = {
    homepage = "https://github.com/Cockatrice/Cockatrice";
    description = "Cross-platform virtual tabletop for multiplayer card games";
    license = lib.licenses.gpl2Plus;
    maintainers = with lib.maintainers; [ evanjs ];
    platforms = with lib.platforms; linux;
    mainProgram = "cockatrice";
  };
}
