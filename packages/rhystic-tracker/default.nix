# Rhystic Tracker — MTG Arena tracker that tails Player.log into a local SQLite
# DB. Finds the log inside Steam's Proton compatdata on its own, so MTGA under
# Proton needs no extra wiring.
#
# Upstream only ships a prebuilt tarball plus an install.sh that scatters files
# into ~/.local, so we build from source. The frontend is its own derivation
# because tauri-build embeds ../dist at compile time — the vite output has to
# exist before cargo runs.
#
# Avatar extraction (Settings -> "extract avatars from MTGA client") stays
# broken here: it shells out to a bundled python script needing UnityPy, which
# nixpkgs doesn't have. Everything else works without it. Drop the note once
# UnityPy lands in nixpkgs.
{
  lib,
  fetchFromGitHub,
  rustPlatform,
  buildNpmPackage,
  makeDesktopItem,
  copyDesktopItems,
  pkg-config,
  wrapGAppsHook3,
  gtk3,
  webkitgtk_4_1,
  libsoup_3,
  glib-networking,
  openssl,
  libayatana-appindicator,
  xdotool,
}: let
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "Balthazzahr";
    repo = "Rhystic-Tracker";
    tag = "v${version}";
    hash = "sha256-jWgC6gwpIh8XypnvjvXFo37BCkfgN0PMrXXIEanFQBo=";
  };

  frontend = buildNpmPackage {
    pname = "rhystic-tracker-ui";
    inherit version src;
    npmDepsHash = "sha256-trA5t03cZ/4X1FvQ/Jkp5qpRXA3P2yxNnhXXAyJwEBI=";
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
  rustPlatform.buildRustPackage {
    pname = "rhystic-tracker";
    inherit version src;

    cargoRoot = "src-tauri";
    buildAndTestSubdir = "src-tauri";
    cargoHash = "sha256-4qRPYIB6sSXHWUPj5KdPoBGLo5a233yGUrzhrdpIAak=";

    # production-env is the feature upstream's release workflow builds with: it
    # selects the real DB instead of the dev one. custom-protocol is what
    # `cargo tauri build` would have passed — without it tauri's build script
    # compiles the app in dev mode and the window tries to load the vite dev
    # server on localhost:5173 instead of the embedded frontend.
    buildFeatures = [
      "production-env"
      "tauri/custom-protocol"
    ];

    postPatch = ''
      cp -r ${frontend} dist
    '';

    nativeBuildInputs = [
      pkg-config
      wrapGAppsHook3
      copyDesktopItems
    ];

    buildInputs = [
      gtk3
      webkitgtk_4_1
      libsoup_3
      glib-networking
      openssl
      libayatana-appindicator
      xdotool
    ];

    # tauri's tray-icon feature dlopens libayatana-appindicator3 rather than
    # linking it, so buildInputs alone leaves it unfindable at runtime.
    preFixup = ''
      gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [libayatana-appindicator]}")
    '';

    postInstall = ''
      for size in 32x32 64x64 128x128; do
        install -Dm644 src-tauri/icons/$size.png \
          $out/share/icons/hicolor/$size/apps/rhystic-tracker.png
      done
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "rhystic-tracker";
        exec = "rhystic-tracker";
        icon = "rhystic-tracker";
        desktopName = "Rhystic Tracker";
        comment = "MTG Arena match tracker and deck analysis";
        categories = ["Game"];
      })
    ];

    meta = {
      description = "Native MTG Arena match tracker, live HUD and deck analysis with local-only storage";
      homepage = "https://github.com/Balthazzahr/Rhystic-Tracker";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "rhystic-tracker";
    };
  }
