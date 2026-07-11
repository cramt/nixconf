{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}: let
  version = "0.32.1";

  src = fetchFromGitHub {
    owner = "kenn-io";
    repo = "agentsview";
    tag = "v${version}";
    hash = "sha256-oAHD+tleolY11RF9Mu5Fxk6iQhxhg2Cf0itaS5SOaNA=";
  };

  frontend = buildNpmPackage {
    pname = "agentsview-frontend";
    inherit version;
    src = "${src}/frontend";

    npmDepsHash = "sha256-UOrVp2DXhqaS/4FdnIiIKTznHEQCt5MBppkg0bLxoao=";

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
  buildGoModule {
    pname = "agentsview";
    inherit version src;

    vendorHash = "sha256-7TxFM/OAso0GT1WlfF7loC8/q2CwhpKTshlTzIGbz+g=";

    subPackages = ["cmd/agentsview"];
    tags = ["fts5"];
    env.CGO_ENABLED = 1;

    ldflags = [
      "-s"
      "-w"
      "-X main.version=v${version}"
    ];

    # The Go binary serves the SPA via go:embed from internal/web/dist
    preBuild = ''
      rm -rf internal/web/dist
      cp -r ${frontend} internal/web/dist
    '';

    # Keep the vendor derivation independent of the frontend build
    overrideModAttrs = _: {preBuild = null;};

    # Tests rely on testcontainers (Docker) and local agent session fixtures
    doCheck = false;

    # frontend is a separate buildNpmPackage with its own npmDepsHash, so point
    # nix-update at it too (`--subpackage frontend`) — otherwise a version bump
    # that changes the frontend lockfile would leave that hash stale.
    passthru.frontend = frontend;
    passthru.updateScript = nix-update-script {
      extraArgs = ["--subpackage" "frontend"];
    };

    meta = {
      description = "Local-first session intelligence and analytics for coding agents";
      homepage = "https://www.agentsview.io/";
      license = lib.licenses.mit;
      mainProgram = "agentsview";
    };
  }
