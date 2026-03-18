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
  nodePackages,
}:
let
  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    rev = "321251907a296b1d0932a42bc20ab2c08f8015ad";
    hash = "sha256-bqrAeOU3lZN4d2yhrqtDou4Nvh9KTG5Xh8m9MDdGKSE=";
  };

  nodeModules = stdenv.mkDerivation {
    name = "t3code-node-modules";
    inherit src;

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
    outputHash = "sha256-wwI1DlJnyADeBl0gr1lkgM5+nxP2IovfDL746zvM6gY=";
  };
in
stdenv.mkDerivation {
  pname = "t3code";
  version = "0.0.10-claude";

  inherit src;

  nativeBuildInputs = [
    bun
    nodejs_24
    makeWrapper
    copyDesktopItems
    python3
    pkg-config
    nodePackages.node-gyp
  ];

  # Spawn the backend server with system node instead of the electron binary,
  # so node-pty only needs to be compiled against the system Node.js ABI.
  postPatch = ''
    substituteInPlace apps/desktop/src/main.ts \
      --replace-fail \
        'ChildProcess.spawn(process.execPath, [backendEntry]' \
        'ChildProcess.spawn("${nodejs_24}/bin/node", [backendEntry]'

    # Bundle all runtime deps into the desktop main process except electron
    # (Electron APIs are provided by the Electron runtime itself).
    substituteInPlace apps/desktop/tsdown.config.ts \
      --replace-fail \
        'noExternal: (id) => id.startsWith("@t3tools/"),' \
        'noExternal: (id) => id !== "electron",'

    # Bundle all runtime deps into the server except node-pty (native addon).
    substituteInPlace apps/server/tsdown.config.ts \
      --replace-fail \
        'noExternal: (id) => id.startsWith("@t3tools/"),' \
        'noExternal: (id) => id !== "node-pty",'
  '';

  configurePhase = ''
    runHook preConfigure

    # Copy root + all workspace node_modules from the FOD
    cp -r ${nodeModules}/node_modules ./node_modules
    for dir in apps/desktop apps/server apps/web apps/marketing \
                packages/contracts packages/shared scripts; do
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

    # ROOT_DIR in main.ts = Path.resolve(__dirname, "../../..")
    # __dirname = apps/desktop/dist-electron/, so:
    # $root/apps/desktop/dist-electron/main.js → ROOT_DIR = $root ✓
    #
    # The server build bundles apps/web/dist into apps/server/dist/client/,
    # so we only need apps/server/dist (no separate web copy needed).
    local root=$out/lib/t3code
    mkdir -p "$root/apps/desktop" "$root/apps/server"

    cp -r apps/desktop/dist-electron "$root/apps/desktop/dist-electron"
    cp -r apps/server/dist           "$root/apps/server/dist"

    # node-pty is the only non-bundled dep (native addon); place it where
    # Node.js will find it relative to apps/server/dist/index.mjs.
    mkdir -p "$root/apps/server/node_modules"
    cp -rL apps/server/node_modules/node-pty "$root/apps/server/node_modules/node-pty"

    # Copy node-pty's own deps (node-addon-api is needed at runtime by node-pty)
    cp -rL apps/server/node_modules/node-addon-api "$root/apps/server/node_modules/node-addon-api" 2>/dev/null || true

    mkdir -p $out/bin
    makeWrapper ${lib.getExe electron} $out/bin/t3code \
      --add-flags "$root/apps/desktop/dist-electron/main.js" \
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
      categories = [ "Development" ];
    })
  ];

  meta = with lib; {
    description = "Minimal web GUI for coding agents with Claude Code support";
    homepage = "https://github.com/pingdotgg/t3code";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3code";
  };
}
