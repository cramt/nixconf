{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_24,
  procps,
  makeWrapper,
}:
# REA (https://github.com/morluto/rea): reverse-engineering CLI + stdio MCP
# server (`rea mcp`). Built from the published npm tarball, which already
# carries the compiled dist/ and the agent skill, so we skip upstream's
# turbo build. The tarball has no lockfile, so we take package-lock.json from
# the release tag; its dependencies match the tarball's package.json exactly.
#
# Install scripts are skipped: the only dependency with one is the optional
# frida, which downloads a prebuilt binding at install time. Frida-backed tools
# stay unavailable; static, Ghidra and JS analysis don't need it.
buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.5.0";

  nodejs = nodejs_24;
  nativeBuildInputs = [makeWrapper];

  src = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${finalAttrs.version}.tgz";
    hash = "sha256-UxcXoG6SymUaq1JpEZD5FvrARCcsAfh14ixeKTIY5pk=";
  };

  lockfile = fetchurl {
    url = "https://raw.githubusercontent.com/morluto/rea/rea-agents-${finalAttrs.version}/package-lock.json";
    hash = "sha256-BIIIU3LFY8mbMlGfUTOesoCtwr2D79umqO/XzUpJ6fA=";
  };

  postPatch = ''
    cp ${finalAttrs.lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-EQKhS1S7Hsfjbo5GikMeAFc2HFtALsDcw6XnJATUryw=";
  npmFlags = ["--ignore-scripts"];
  npmRebuildFlags = ["--ignore-scripts"];
  dontNpmBuild = true;

  # Linux process-ownership checks shell out to a procps `ps` (upstream
  # docs/installation.md, "Linux owned-process prerequisite").
  postFixup = ''
    for b in $out/bin/*; do
      wrapProgram $b --prefix PATH : ${lib.makeBinPath [procps]}
    done
  '';

  passthru.skill = "${finalAttrs.finalPackage}/lib/node_modules/rea-agents/skills/reverse-engineer-anything";

  meta = {
    description = "Reverse engineer anything: CLI and MCP server for binaries, apps and runtime behaviour";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    mainProgram = "rea";
  };
})
