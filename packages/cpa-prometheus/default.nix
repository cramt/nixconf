{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
# CLIProxyAPI plugin: an in-process c-shared library, not an executable. CPA
# picks plugins up by scanning plugins.dir for regular *.so files (symlinks are
# skipped) and takes the plugin id from the file name, so the library lands as
# lib/cpa-prometheus.so and modules/hm-features/cli-proxy-api.nix copies it into
# a plugins dir rather than linking it.
buildGoModule (finalAttrs: {
  pname = "cpa-prometheus";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "giovannirco";
    repo = "cpa-prometheus-plugin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-SugvNWYXvB+UyU7IWn21io3TXFlAd0RzFtou/x3iC1M=";
  };

  vendorHash = "sha256-nbGJDnFfVUQ2UiTjq+CuUr/+PKNLsGNQ76HyQxRBoRU=";

  # c-shared needs cgo, which buildGoModule already enables on linux; the
  # version ldflag is what the plugin reports in its registration metadata.
  ldflags = [
    "-s"
    "-w"
    "-X github.com/giovannirco/cpa-prometheus-plugin/internal/plugin.PluginVersion=${finalAttrs.version}"
  ];

  buildPhase = ''
    runHook preBuild
    mkdir -p $out/lib
    go build -buildmode=c-shared -trimpath -ldflags="''${ldflags[*]}" \
      -o $out/lib/cpa-prometheus.so ./cmd/plugin
    rm -f $out/lib/cpa-prometheus.h
    runHook postBuild
  '';

  # The stock checkPhase leans on helpers the stock buildPhase defines.
  # internal/release only lints the store-release layout, and finds
  # registry.json via its own source path, which -trimpath rewrites away.
  checkPhase = ''
    runHook preCheck
    go test $(go list ./... | grep -v /internal/release)
    runHook postCheck
  '';

  # The default installPhase would `go install` subPackages as binaries.
  installPhase = ''
    runHook preInstall
    runHook postInstall
  '';

  meta = {
    description = "CLIProxyAPI plugin exporting request, token, credential and quota metrics for Prometheus";
    homepage = "https://github.com/giovannirco/cpa-prometheus-plugin";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
