# Delta — Zed's standalone AI coding agent (https://delta.dev). Not the same
# thing as pkgs.delta, which is dandavison's git-delta pager; this one is
# exposed as `zed-delta` so it doesn't shadow that, but its binary is still
# named `delta`, so only put one of the two on a given PATH.
#
# The tarball sits in a private R2 bucket. delta.dev's (unauthenticated)
# releases API only ever hands out presigned links that die after 15 minutes,
# so there is no URL fetchurl could pin. Instead src is a fixed-output
# derivation that asks the API for a fresh link to the *pinned* version at
# fetch time: the hash keeps it reproducible, the API just brokers access.
# Swap for plain fetchurl if upstream ever publishes a stable URL.
#
# Upstream ships bin/delta with RPATH=$ORIGIN/../lib and its own copies of
# libxcb/libxkbcommon/libunwind (built for old-glibc distros). We drop that lib/
# directory and let autoPatchelf link the nixpkgs ones instead — all three are
# stable-soname libraries, and vendoring them here would just freeze a second
# unpatched copy into the closure.
#
# GPUI reaches libwayland-client/libwayland-egl/libvulkan/libEGL through dlopen,
# which autoPatchelf cannot see, so those four go in the wrapper's
# LD_LIBRARY_PATH along with the driver link that carries the Vulkan ICD.
#
# Bumped by `just update_packages`: the API's nightly/latest answers the
# version, nix-update rewrites version + hash.
{
  lib,
  stdenv,
  stdenvNoCC,
  curl,
  jq,
  cacert,
  autoPatchelfHook,
  makeWrapper,
  addDriverRunpath,
  libxkbcommon,
  llvmPackages,
  libglvnd,
  vulkan-loader,
  wayland,
  xorg,
}: let
  version = "0.17.0";
in
  stdenv.mkDerivation {
    pname = "zed-delta";
    inherit version;

    src = stdenvNoCC.mkDerivation {
      name = "delta-linux-x86_64-${version}.tar.gz";
      outputHashMode = "flat";
      outputHashAlgo = "sha256";
      outputHash = "sha256-+AUZre1HCN2hzmF95jY0Xs0n4Fd/yPnfCTG+QGBt6MU=";
      nativeBuildInputs = [curl jq];
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      impureEnvVars = lib.fetchers.proxyImpureEnvVars;
      buildCommand = ''
        url=$(curl -fsSL "https://delta.dev/api/releases/nightly/${version}/asset?asset=delta&os=linux&arch=x86_64" | jq -er .url)
        curl -fsSL -o "$out" "$url"
      '';
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];

    buildInputs = [
      xorg.libxcb
      libxkbcommon
      # LLVM's libunwind, not nixpkgs' nongnu `libunwind` — only the LLVM one
      # carries soname libunwind.so.1, which is what upstream linked against.
      llvmPackages.libunwind
    ];

    # The tarball's install.sh only copies the bundle into ~/.local and rewrites
    # the .desktop Exec; we do the same thing declaratively and skip the script.
    installPhase = ''
      runHook preInstall

      rm -rf lib
      mkdir -p $out/bin $out/share
      cp -a bin/delta $out/bin/delta
      cp -a share/icons $out/share/icons

      install -Dm644 share/applications/dev.zed.Delta.desktop \
        $out/share/applications/dev.zed.Delta.desktop
      substituteInPlace $out/share/applications/dev.zed.Delta.desktop \
        --replace-fail "Exec=delta " "Exec=$out/bin/delta "

      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/delta \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [wayland vulkan-loader libglvnd]}:${addDriverRunpath.driverLink}/lib"
    '';

    meta = {
      description = "Zed's standalone AI coding agent";
      homepage = "https://delta.dev";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "delta";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
