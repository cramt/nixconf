{
  lib,
  buildNpmPackage,
  nodejs_22,
  makeWrapper,
}:
buildNpmPackage {
  pname = "titan-frontend";
  version = "1.0.0";

  src = ./.;

  nodejs = nodejs_22;

  npmDepsHash = "sha256-ZhCj9GWaU79N5NcWrRDZp1oBDahZf2L/6+rVgTqrfWY=";

  # Build the TypeScript project
  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  # Don't run default npm install phase since we handle it
  dontNpmInstall = true;

  # Install the built output
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/titan-frontend
    cp -r dist $out/lib/titan-frontend/
    cp -r node_modules $out/lib/titan-frontend/
    cp package.json $out/lib/titan-frontend/
    cp ai-plugin.json $out/lib/titan-frontend/

    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/titan-frontend \
      --add-flags "$out/lib/titan-frontend/dist/index.js"

    runHook postInstall
  '';

  nativeBuildInputs = [makeWrapper];

  meta = with lib; {
    description = "HTTP frontend for Titan VM SSH/VNC access - Microsoft 365 Copilot API Plugin";
    homepage = "https://github.com/cramt/nixconf";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.linux;
    mainProgram = "titan-frontend";
  };
}
