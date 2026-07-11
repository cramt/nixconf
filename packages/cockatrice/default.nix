{
  lib,
  stdenv,
  qt6,
  cmake,
  protobuf,
  openssl,
  fetchFromGitHub,
  nix-update-script,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cockatrice";
  # nixpkgs' cockatrice lags a full major version behind (2.10.x), so we build
  # from source. Cockatrice tags every build YYYY-MM-DD-{Release,Development}-X.Y.Z;
  # the `version` here is the full stable *Release* tag. `just update_packages`
  # runs nix-update, which follows GitHub's "latest release" (Development tags are
  # marked pre-release and skipped).
  version = "2026-06-26-Release-3.0.2";

  src = fetchFromGitHub {
    owner = "Cockatrice";
    repo = "Cockatrice";
    tag = finalAttrs.version;
    hash = "sha256-qn8pnC04uN994qLK4oXc3IiTpPMT3/gqHHBaEDkjsr4=";
  };

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

  passthru.updateScript = nix-update-script {};

  meta = {
    homepage = "https://github.com/Cockatrice/Cockatrice";
    description = "Cross-platform virtual tabletop for multiplayer card games";
    license = lib.licenses.gpl2Plus;
    maintainers = with lib.maintainers; [ evanjs ];
    platforms = with lib.platforms; linux;
    mainProgram = "cockatrice";
  };
})
