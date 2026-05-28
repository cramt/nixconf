{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  glib,
  libxkbcommon,
  vulkan-loader,
  wayland,
  libx11,
  libxcb,
  zlib,
}:
# Prebuilt Zed binary from the official GitHub releases. Bypasses the source
# build (crane + livekit-rust-sdks LFS mess). Tracks the "preview" channel —
# bump version + hash whenever a new -pre tag drops:
#
#   nix-prefetch-url --type sha256 \
#     "https://github.com/zed-industries/zed/releases/download/v<VERSION>/zed-linux-x86_64.tar.gz" \
#     | xargs nix hash to-sri --type sha256
let
  version = "1.5.0-pre";
in
  stdenv.mkDerivation {
    pname = "zed-editor";
    inherit version;

    src = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/zed-linux-x86_64.tar.gz";
      hash = "sha256-zCdpB5X6TWWf3z5XKfAdkjVQOjnLCwTkm6A3vdoC5hg=";
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];

    buildInputs = [
      alsa-lib
      glib
      libxkbcommon
      stdenv.cc.cc.lib
      vulkan-loader
      wayland
      libx11
      libxcb
      zlib
    ];

    # Loaded at runtime (dlopen) — autoPatchelfHook only catches NEEDED.
    runtimeDependencies = [vulkan-loader wayland libxkbcommon];

    dontConfigure = true;
    dontBuild = true;

    # The tarball's single top-level dir is auto-stripped, so we're already
    # inside the .app directory at install time. Strip the bundled lib/ —
    # autoPatchelfHook rewires the ELFs to nixpkgs deps, and keeping these
    # collides with other packages in the home-manager profile (libxcb etc.).
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r . $out/
      rm -rf $out/lib
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/libexec/zed-editor \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [vulkan-loader wayland libxkbcommon]}"
    '';

    meta = {
      description = "Zed editor (official prebuilt preview binary)";
      homepage = "https://zed.dev";
      license = lib.licenses.gpl3Plus;
      platforms = ["x86_64-linux"];
      mainProgram = "zed";
    };
  }
