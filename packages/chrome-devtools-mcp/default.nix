{
  stdenvNoCC,
  lib,
  fetchurl,
  makeWrapper,
  nodejs,
  ungoogled-chromium,
  # Same default as agent-browser, so both CDP drivers share one chromium.
  chromium ? ungoogled-chromium,
}:
# Google's Chrome DevTools MCP server. Not in nixpkgs. The npm tarball is
# fully bundled (no runtime dependencies), so it only needs node and a
# browser. Without --executablePath it looks for Chrome's stable channel at
# /opt/google/chrome/chrome, which doesn't exist on NixOS.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "chrome-devtools-mcp";
  version = "1.12.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-Sq3jFnw+eBx5fWEJ7WA6DKW4yzY6KJ4uqsqpsMXSo2A=";
  };

  nativeBuildInputs = [makeWrapper];

  dontConfigure = true;
  dontBuild = true;

  # The update check nags to `npm install chrome-devtools-mcp@latest`, which
  # isn't how this gets bumped; nix-update in `just update_packages` is.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/chrome-devtools-mcp
    cp -r . $out/lib/node_modules/chrome-devtools-mcp

    makeWrapper ${lib.getExe nodejs} $out/bin/chrome-devtools-mcp \
      --add-flags $out/lib/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js \
      --add-flags "--executablePath ${lib.getExe chromium}" \
      --set CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS 1

    runHook postInstall
  '';

  meta = {
    description = "Chrome DevTools MCP server, wired to a nix chromium";
    homepage = "https://github.com/ChromeDevTools/chrome-devtools-mcp";
    license = lib.licenses.asl20;
    mainProgram = "chrome-devtools-mcp";
  };
})
