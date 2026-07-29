{
  lib,
  stdenv,
  cacert,
  makeWrapper,
  nodejs_24,
  python3,
  node-gyp,
  gnumake,
  # `inputs.pnpm2nix.lib.<system>` — pure-Nix pnpm-lock.yaml v9 builder.
  pnpm2nix,
  # `inputs.t3code-src` — the upstream monorepo (flake = false).
  src,
}:
# T3 Code is a pnpm 11 monorepo with no upstream Nix packaging and no published
# binary, so it's built from source via pnpm2nix, which reconstructs pnpm's
# node_modules layout from the lockfile without running `pnpm install`.
#
# The shipped `t3` CLI is two pieces glued together: apps/server bundled by
# `vp pack`, plus apps/web's static build served as dist/client. Upstream does
# that in `apps/server/scripts/cli.ts build` (a vite-plus task that dependsOn
# @t3tools/web#build). pnpm2nix builds each app in isolation, so the two halves
# are built separately here and joined at install time.
let
  version = (lib.importJSON (src + "/apps/server/package.json")).version;

  nodejs = nodejs_24;

  # node-pty resolves its addon under prebuilds/<process.platform>-<process.arch>,
  # which are node's names, not nix's.
  nodePrebuildDir =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${stdenv.hostPlatform.system}
    or (throw "t3code: no node-pty prebuild dir mapping for ${stdenv.hostPlatform.system}");

  workspace = pnpm2nix.mkPnpmWorkspace {
    workspace = src;
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

    # vite-plus builds a reqwest HTTP client during startup and panics outright
    # if the system trust store is empty, which it is in the sandbox. Nothing is
    # fetched — the build has no network — this only gets it past init.
    buildEnv = {
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
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
in
  stdenv.mkDerivation {
    pname = "t3code";
    inherit version;

    dontUnpack = true;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/t3code/dist
      cp -r ${workspace.apps.server}/. $out/lib/t3code/dist/
      cp -r ${workspace.apps.web} $out/lib/t3code/dist/client

      # `vp pack` externalizes runtime deps, so bin.mjs needs a node_modules to
      # resolve against; node walks up from dist/ and finds this one. Built as a
      # shallow symlink layer rather than linked wholesale so that node-pty can
      # be swapped for a copy carrying the native addon.
      nm=$out/lib/t3code/node_modules
      mkdir -p $nm
      farm=${workspace.nodeModules."apps/server"}/node_modules
      for entry in $farm/* $farm/.[!.]*; do
        [ -e "$entry" ] || continue
        ln -s "$entry" "$nm/$(basename "$entry")"
      done

      rm "$nm/node-pty"
      cp -rL "$farm/node-pty" "$nm/node-pty"
      chmod -R u+w "$nm/node-pty"
      # node-pty's loader probes build/Release, build/Debug, then
      # prebuilds/<process.platform>-<process.arch>.
      install -Dm444 ${nodePty}/pty.node \
        "$nm/node-pty/prebuilds/${nodePrebuildDir}/pty.node"

      makeWrapper ${nodejs}/bin/node $out/bin/t3 \
        --add-flags $out/lib/t3code/dist/bin.mjs

      runHook postInstall
    '';

    meta = {
      description = "Self-hosted orchestrator for coding agents, with a web UI";
      homepage = "https://t3.codes";
      license = lib.licenses.mit;
      mainProgram = "t3";
      # Only x86_64-linux is actually exercised; aarch64 should work (node-pty is
      # compiled from source either way) but is unverified.
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  }
