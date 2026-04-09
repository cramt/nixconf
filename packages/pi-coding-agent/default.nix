{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.66.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@mariozechner/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-NN26A3EQft5Bhyu53JmNECd1kgkNPPse6BsDnwGbzyE=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-lDDntigbBzlzw28kRw+Gl0TJokYHZv+3RpYglH0hDLE=";
  dontNpmBuild = true;

  meta = {
    description = "Pi - a minimal terminal-based coding agent";
    homepage = "https://github.com/badlogic/pi-mono";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
