{
  lib,
  stdenv,
  cacert,
  jq,
  runCommand,
  makeWrapper,
  nodejs_24,
  python3,
  node-gyp,
  gnumake,
  electron_41,
  makeDesktopItem,
  copyDesktopItems,
  # `inputs.pnpm2nix.lib.<system>` — pure-Nix pnpm-lock.yaml v9 builder.
  pnpm2nix,
  # `inputs.t3code-src` — the upstream monorepo (flake = false).
  src,
}:
# T3 Code is a pnpm 11 monorepo with no upstream Nix packaging and no published
# binary, so it's built from source via pnpm2nix, which reconstructs pnpm's
# node_modules layout from the lockfile without running `pnpm install`.
#
# Two programs come out of this:
#
#   t3              — the CLI/server. `vp pack` bundles apps/server, and
#                     apps/web's static build is served as dist/client.
#                     Upstream glues those in `apps/server/scripts/cli.ts
#                     build` (a vite-plus task that dependsOn @t3tools/web
#                     #build); pnpm2nix builds each app in isolation, so the
#                     two halves are built separately and joined at install.
#   t3code-desktop  — the Electron shell (apps/desktop). It spawns the same
#                     server bundle as a child process and points a window at
#                     it, so it needs that bundle reachable at the path layout
#                     it expects (see the install phase).
let
  version = (lib.importJSON (src + "/apps/server/package.json")).version;

  nodejs = nodejs_24;
  electron = electron_41;

  # node-pty resolves its addon under prebuilds/<process.platform>-<process.arch>,
  # which are node's names, not nix's.
  nodePrebuildDir =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${stdenv.hostPlatform.system}
    or (throw "t3code: no node-pty prebuild dir mapping for ${stdenv.hostPlatform.system}");

  # apps/desktop's build is a vite-plus `run.tasks.build` in vite.config.ts, not
  # a package.json script, and it `dependsOn: ["t3#build"]` — which pnpm2nix
  # can't satisfy because it builds each app from an isolated source tree. Add a
  # script for the app's own half of that task (`vp pack`, plus the CSS step it
  # shells out to first); the server/web half is built separately and joined at
  # install time, same as for the CLI.
  patchedSrc =
    runCommand "t3code-src-${version}-nix-pack" {
      nativeBuildInputs = [jq];
    } ''
      cp -r --no-preserve=mode,ownership ${src} $out
      jq '.scripts["nix:pack"] = "node scripts/build-preview-annotation-css.mjs && vp pack"' \
        ${src}/apps/desktop/package.json > $out/apps/desktop/package.json
    '';

  workspace = pnpm2nix.mkPnpmWorkspace {
    workspace = patchedSrc;
    inherit nodejs;

    apps = [
      {
        name = "web";
        path = "apps/web";
        script = "build";
        distDir = "dist";
      }
      {
        name = "server";
        path = "apps/server";
        inherit version;
        # The `build` task lives in vite.config.ts, not package.json, and pulls
        # in the web app; `build:bundle` is the `vp pack` step on its own.
        script = "build:bundle";
        distDir = "dist";
      }
      {
        name = "desktop";
        path = "apps/desktop";
        inherit version;
        script = "nix:pack";
        distDir = "dist-electron";
      }
    ];

    packages = [
      "packages/client-runtime"
      "packages/contracts"
      "packages/effect-acp"
      "packages/effect-codex-app-server"
      "packages/shared"
      "packages/ssh"
      "packages/tailscale"
      "oxlint-plugin-t3code"
      "scripts"
    ];

    # apps/desktop/src/main.ts does `import serverPackageJson from
    # "../../server/package.json"`, so the desktop build needs the server dir
    # in its source tree. pnpm2nix's default per-app isolation strips sibling
    # apps, so hand every app the whole workspace instead. The only thing lost
    # is build-cache granularity between apps, and a src bump already rebuilds
    # all of them.
    appSrc = _: patchedSrc;

    buildEnv = {
      # vite-plus builds a reqwest HTTP client during startup and panics outright
      # if the system trust store is empty, which it is in the sandbox. Nothing is
      # fetched — the build has no network — this only gets it past init.
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

      # T3 Connect (Clerk sign-in + the managed cloud relay) is compiled in from
      # these, not configured at runtime: `scripts/lib/public-config.ts` reads
      # them and each app's vite.config.ts bakes them into `__T3CODE_BUILD_*__`
      # defines. Upstream's own way to turn the feature on is `cp .env.example
      # .env`; loadRepoEnv takes process.env at higher precedence than that file,
      # so setting them here does the same thing without patching the source.
      # Leave any of them out and its define becomes "", which is how the feature
      # ships disabled. Values are the public identifiers from .env.example —
      # the same ones in official release builds, not secrets.
      T3CODE_CLERK_PUBLISHABLE_KEY = "pk_live_Y2xlcmsudDMuY29kZXMk";
      T3CODE_CLERK_JWT_TEMPLATE = "t3-relay";
      T3CODE_CLERK_CLI_OAUTH_CLIENT_ID = "hzxSgY2cH10sDU2r";
      T3CODE_RELAY_URL = "https://relay.t3.codes";
    };
  };

  # Resolve a lockfile package by name so a version bump upstream fails loudly
  # here instead of silently dropping the native addon.
  extractedPkg = name: let
    matches =
      lib.filter (k: lib.hasPrefix "${name}@" k)
      (builtins.attrNames workspace.passthru.extracted);
  in
    if matches == []
    then throw "t3code: ${name} is no longer in pnpm-lock.yaml — the node-pty graft needs revisiting"
    else workspace.passthru.extracted.${lib.head matches};

  # node-pty ships prebuilds for darwin/win32 only; everywhere else its `install`
  # script runs `node-gyp rebuild`. pnpm2nix deliberately never runs lifecycle
  # scripts, so the addon is compiled here and grafted in below. Without it the
  # server aborts at startup with NodePtyModuleLoadError.
  #
  # The CLI runs the server bundle under plain node, while the desktop app spawns
  # it as `process.execPath` with ELECTRON_RUN_AS_NODE=1 (see
  # DesktopBackendConfiguration.ts) — i.e. under Electron's node, at a different
  # NODE_MODULE_VERSION. One build covers both anyway: node-pty is a
  # node-addon-api (Node-API) addon, and Node-API is ABI-stable across runtimes
  # (verified by dlopen'ing this addon under both node 24 and electron 41).
  nodePty = stdenv.mkDerivation {
    pname = "t3code-node-pty";
    inherit version;
    src = extractedPkg "node-pty";

    nativeBuildInputs = [nodejs python3 node-gyp gnumake];

    buildPhase = ''
      runHook preBuild

      export HOME=$TMPDIR
      chmod -R u+w .

      # binding.gyp reads node-addon-api's header path out of the module itself
      # (`node -p "require('node-addon-api').targets"`), so it has to resolve.
      mkdir -p node_modules
      ln -sfn ${extractedPkg "node-addon-api"} node_modules/node-addon-api

      node-gyp rebuild --nodedir=${nodejs}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      # spawn-helper is an OS=="mac" target in binding.gyp; elsewhere the addon
      # is the entire build output.
      install -Dm444 build/Release/pty.node $out/pty.node
      runHook postInstall
    '';
  };

  # Desktop branding moved out of apps/desktop/resources into a per-channel
  # assets/ tree upstream (resources/ now holds only the macOS dmg backgrounds).
  # This build is unpackaged — Electron gets a script path, so isPackaged is
  # false and isDevelopment needs VITE_DEV_SERVER_URL, which is unset — and for
  # that case DesktopAssets.ts resolves the window icon as
  # <rootDir>/assets/<brand>/<universalPng>, i.e. the path below. "universal" is
  # the non-darwin export; the macos-1024 sibling carries mac's safe-area inset.
  desktopIconPath = "assets/prod/black-universal-1024.png";

  desktopItem = makeDesktopItem {
    name = "t3code";
    exec = "t3code-desktop %U";
    icon = "t3code";
    desktopName = "T3 Code (Alpha)";
    comment = "Self-hosted orchestrator for coding agents";
    categories = ["Development"];
    # DesktopEnvironment.ts pins these for the unpackaged Linux build: the
    # window's WM class is `t3code` and it registers the `t3code://` scheme.
    startupWMClass = "t3code";
    mimeTypes = ["x-scheme-handler/t3code"];
  };
in
  stdenv.mkDerivation {
    pname = "t3code";
    inherit version;

    dontUnpack = true;

    nativeBuildInputs = [makeWrapper copyDesktopItems];
    desktopItems = [desktopItem];

    installPhase = ''
      runHook preInstall

      # `vp pack` externalizes runtime deps, so the bundles need a node_modules
      # to resolve against; node walks up from the bundle's directory and finds
      # the one built here. Laid out as a shallow symlink layer rather than
      # linked wholesale so that node-pty can be swapped for a copy carrying the
      # native addon.
      linkNodeModules() {
        local farm=$1 nm=$2
        mkdir -p "$nm"
        for entry in $farm/* $farm/.[!.]*; do
          [ -e "$entry" ] || continue
          ln -s "$entry" "$nm/$(basename "$entry")"
        done
      }

      # node-pty's loader probes build/Release, build/Debug, then
      # prebuilds/<process.platform>-<process.arch>.
      graftNodePty() {
        local farm=$1 nm=$2 addon=$3
        rm "$nm/node-pty"
        cp -rL "$farm/node-pty" "$nm/node-pty"
        chmod -R u+w "$nm/node-pty"
        install -Dm444 "$addon" "$nm/node-pty/prebuilds/${nodePrebuildDir}/pty.node"
      }

      serverFarm=${workspace.nodeModules."apps/server"}/node_modules

      # --- t3: the CLI, server bundle + web client under one root ------------
      mkdir -p $out/lib/t3code/dist
      cp -r ${workspace.apps.server}/. $out/lib/t3code/dist/
      cp -r ${workspace.apps.web} $out/lib/t3code/dist/client

      linkNodeModules "$serverFarm" $out/lib/t3code/node_modules
      graftNodePty "$serverFarm" $out/lib/t3code/node_modules ${nodePty}/pty.node

      makeWrapper ${nodejs}/bin/node $out/bin/t3 \
        --add-flags $out/lib/t3code/dist/bin.mjs

      # --- t3code-desktop: the Electron shell -------------------------------
      # Electron started with a script path leaves app.isPackaged false, so
      # DesktopEnvironment.ts derives appRoot as ../../.. from main.cjs and
      # looks for the backend at <appRoot>/apps/server/dist/bin.mjs. Mirror the
      # repo's own unpackaged layout so those paths land inside the store.
      desktopRoot=$out/lib/t3code-desktop
      mkdir -p $desktopRoot/apps/desktop $desktopRoot/apps/server

      cp -r ${workspace.apps.desktop} $desktopRoot/apps/desktop/dist-electron
      # Probed as ../resources relative to main.cjs (DesktopAssets.ts), which is
      # now only the fallback — the icon lookup hits <rootDir>/assets first.
      cp -r ${patchedSrc}/apps/desktop/resources $desktopRoot/apps/desktop/resources
      cp ${patchedSrc}/apps/desktop/package.json $desktopRoot/apps/desktop/package.json
      # rootDir is desktopRoot (resolve(dist-electron, "../../..")), so the
      # prod branding has to sit here for the window icon to resolve. Only the
      # prod channel: dev/nightly are selected by env vars a store build
      # never sets.
      mkdir -p $desktopRoot/assets
      cp -r ${patchedSrc}/assets/prod $desktopRoot/assets/prod
      linkNodeModules "${workspace.nodeModules."apps/desktop"}/node_modules" \
        $desktopRoot/apps/desktop/node_modules

      # The backend it spawns is byte-identical to the CLI's, so point at that
      # tree instead of duplicating the server bundle and web client. node
      # resolves symlinks before walking up for node_modules, so the deps found
      # from here are the CLI tree's.
      ln -s $out/lib/t3code/dist $desktopRoot/apps/server/dist
      ln -s $out/lib/t3code/node_modules $desktopRoot/apps/server/node_modules
      cp ${patchedSrc}/apps/server/package.json $desktopRoot/apps/server/package.json

      makeWrapper ${electron}/bin/electron $out/bin/t3code-desktop \
        --add-flags $desktopRoot/apps/desktop/dist-electron/main.cjs \
        --add-flags "\''${NIXOS_OZONE_WL:+--ozone-platform-hint=auto}"

      install -Dm444 ${patchedSrc}/${desktopIconPath} \
        $out/share/pixmaps/t3code.png

      runHook postInstall
    '';

    meta = {
      description = "Self-hosted orchestrator for coding agents, with a web UI and Electron desktop app";
      homepage = "https://t3.codes";
      license = lib.licenses.mit;
      mainProgram = "t3";
      # Only x86_64-linux is actually exercised; aarch64 should work (node-pty is
      # compiled from source either way) but is unverified.
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  }
