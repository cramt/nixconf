# Delta — Zed's standalone AI coding agent (https://delta.dev). Not the same
# thing as pkgs.delta, which is dandavison's git-delta pager; this one is
# exposed as `zed-delta` so it doesn't shadow that, but its binary is still
# named `delta`, so only put one of the two on a given PATH.
#
# requireFile, not fetchurl: Delta is invite-only early access and
# https://delta.dev/api/releases/stable/latest/delta-linux-x86_64.tar.gz answers
# 401 without a session cookie, so there is no URL Nix can fetch unattended.
# Swap this for a plain fetchurl once downloads open up.
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
# Bump: set version, download the new tarball, then
#   nix-store --add-fixed sha256 delta-linux-x86_64.tar.gz
#   nix hash file --type sha256 --sri delta-linux-x86_64.tar.gz
{
  lib,
  stdenv,
  requireFile,
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
  version = "0.15.0";
in
  stdenv.mkDerivation {
    pname = "zed-delta";
    inherit version;

    src = requireFile {
      name = "delta-linux-x86_64.tar.gz";
      hash = "sha256-necopupdJDzqS7yG2ilDfL4c767S3qz+lNfype32LXw=";
      message = ''
        Delta is invite-only, so its tarball cannot be fetched automatically.
        Download delta-linux-x86_64.tar.gz while signed in at
        https://delta.dev/download and add it to the store with:

          nix-store --add-fixed sha256 delta-linux-x86_64.tar.gz
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
