{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  nix-update-script,
}:
# Built from the official release tarball rather than from source. As of 0.37.x
# the source build is impractical to sandbox: the frontend bundles a git-only
# dependency and uses vite-plus (whose Rust core panics without a CA bundle), and
# the Go build embeds a LiteLLM pricing snapshot fetched over the network at
# generate time. The release tarball ships a single Go binary with the frontend
# and pricing already embedded, so we patchelf that. nix-update follows the
# GitHub releases and rewrites version + the host-arch hash below.
let
  version = "0.37.5";

  selectSystem = attrs:
    attrs.${stdenv.hostPlatform.system}
      or (throw "agentsview: unsupported system ${stdenv.hostPlatform.system}");

  arch = selectSystem {
    x86_64-linux = "amd64";
    aarch64-linux = "arm64";
  };
  # nix-update updates the entry matching the build host (x86_64 on saturn); the
  # aarch64 hash only moves when built on arm. Every host that uses agentsview is
  # x86_64, so arm is effectively spare coverage.
  hash = selectSystem {
    x86_64-linux = "sha256-qrQ8/DALLRO5sJgmSumIz0+iOQ/KE/9gqedus2GbJXw=";
    aarch64-linux = "sha256-EvOMxiP0zp0J6FcUSSX4AqwA+SlMoxPwYNY3JhwqAD4=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "agentsview";
    inherit version;

    src = fetchurl {
      url = "https://github.com/kenn-io/agentsview/releases/download/v${finalAttrs.version}/agentsview_${finalAttrs.version}_linux_${arch}.tar.gz";
      inherit hash;
    };

    # Tarball is a bare `agentsview` binary with no top-level directory.
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [stdenv.cc.cc.lib]; # libstdc++ / libgcc_s for the CGO sqlite (fts5)

    installPhase = ''
      runHook preInstall
      install -Dm755 agentsview $out/bin/agentsview
      runHook postInstall
    '';

    passthru.updateScript = nix-update-script {};

    meta = {
      description = "Local-first session intelligence and analytics for coding agents";
      homepage = "https://www.agentsview.io/";
      license = lib.licenses.mit;
      mainProgram = "agentsview";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  })
