{
  lib,
  stdenv,
  fetchFromGitHub,
  bun,
  nodejs_24,
  electron,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  python3,
  pkg-config,
  node-gyp,
}: let
  version = "0.0.22-nightly.20260427.140-unstable-2026-04-27";
  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    rev = "dbebc387dd458dd7062380ccb862a5cdac7aba66";
    hash = "sha256-UR7HsnJq1RSiTMCi7LqVDQbx4IxmIC8aK67tqbqsv98=";
    fetchSubmodules = true;
  };

  nodeModules = stdenv.mkDerivation {
    pname = "t3code-node-modules";
    inherit version src;

    nativeBuildInputs = [
      bun
      nodejs_24
    ];

    dontPatchShebangs = true;

    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile --ignore-scripts
    '';

    installPhase = ''
      cp -r . $out
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-Y26xklsEBJYkyznls3s45P4eq2Pa3arFfLIu1VPUSy4=";
  };
in
  stdenv.mkDerivation {
    pname = "t3code";
    inherit version src;

    nativeBuildInputs = [
      bun
      nodejs_24
      makeWrapper
      copyDesktopItems
      python3
      pkg-config
      node-gyp
    ];

    # Spawn the backend server with system node instead of the electron binary,
    # so node-pty only needs to be compiled against the system Node.js ABI.
    postPatch = ''
      substituteInPlace apps/desktop/src/main.ts \
        --replace-fail \
          'ChildProcess.spawn(process.execPath, [backendEntry, "--bootstrap-fd", "3"]' \
          'ChildProcess.spawn("${nodejs_24}/bin/node", [backendEntry, "--bootstrap-fd", "3"]'

      # Bundle all runtime deps into the desktop main process except electron
      # (Electron APIs are provided by the Electron runtime itself).
      substituteInPlace apps/desktop/tsdown.config.ts \
        --replace-fail \
          'noExternal: (id) => id.startsWith("@t3tools/") || id.startsWith("effect-acp"),' \
          'noExternal: (id) => id !== "electron",'

      # Bundle all runtime deps into the server except node-pty (native addon).
      substituteInPlace apps/server/tsdown.config.ts \
        --replace-fail \
          'noExternal: (id) => id.startsWith("@t3tools/") || id.startsWith("effect-acp"),' \
          'noExternal: (id) => id !== "node-pty",'
    '';

    configurePhase = ''
      runHook preConfigure

      # Copy root + all workspace node_modules from the FOD
      cp -r ${nodeModules}/node_modules ./node_modules
      for dir in apps/* packages/* scripts; do
        if [ -d "${nodeModules}/$dir/node_modules" ]; then
          cp -r "${nodeModules}/$dir/node_modules" "./$dir/node_modules"
        fi
      done
      chmod -R +w node_modules apps/*/node_modules packages/*/node_modules scripts/node_modules 2>/dev/null || true

      # Patch shebangs (FOD skipped this to avoid store refs; .bin/ are symlinks
      # so we patch the full trees, not just .bin/)
      for nm in node_modules apps/*/node_modules packages/*/node_modules scripts/node_modules; do
        [ -d "$nm" ] && patchShebangs "$nm"
      done

      # Rebuild node-pty native module (in apps/server) against system Node.js
      export HOME=$TMPDIR
      pushd apps/server/node_modules/node-pty
      node-gyp rebuild --nodedir=${nodejs_24}/include/node
      popd

      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild

      export HOME=$TMPDIR
      export ELECTRON_SKIP_BINARY_DOWNLOAD=1

      # Build everything in dependency order (turbo resolves the order)
      bun run build

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      local root=$out/lib/t3code
      mkdir -p "$root/apps/desktop" "$root/apps/server"

      cp -r apps/desktop/dist-electron "$root/apps/desktop/dist-electron"
      cp -r apps/server/dist           "$root/apps/server/dist"

      # node-pty is the only non-bundled dep (native addon)
      mkdir -p "$root/apps/server/node_modules"
      cp -rL apps/server/node_modules/node-pty "$root/apps/server/node_modules/node-pty"
      cp -rL apps/server/node_modules/node-addon-api "$root/apps/server/node_modules/node-addon-api" 2>/dev/null || true

      mkdir -p $out/bin
      makeWrapper ${lib.getExe electron} $out/bin/t3code \
        --add-flags "$root/apps/desktop/dist-electron/main.cjs" \
        --chdir "$root" \
        --set ELECTRON_IS_DEV 0 \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "t3code";
        exec = "t3code";
        desktopName = "T3 Code";
        comment = "Minimal web GUI for coding agents";
        categories = ["Development"];
      })
    ];

    # Exposed so `nix-update t3code -s passthru.nodeModules` can bump the FOD hash.
    passthru = {inherit nodeModules;};

    meta = with lib; {
      description = "Minimal web GUI for coding agents with Claude Code support";
      homepage = "https://github.com/pingdotgg/t3code";
      license = licenses.mit;
      platforms = ["x86_64-linux"];
      mainProgram = "t3code";
    };
  }
