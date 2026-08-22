{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  cloudflared,
  which,
  nix-update-script,
}:
# manycode — shares a live terminal running claude (or codex/opencode/aider…)
# with a join code, over the LAN or a cloudflare quick tunnel. Not in nixpkgs
# and no upstream flake; it's a plain node CLI, so buildNpmPackage off the tag.
# The macOS menu bar helper and the .app under app/ are dead weight on linux —
# the CLI checks the platform before reaching for them.
buildNpmPackage (finalAttrs: {
  pname = "manycode";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "unworld11";
    repo = "manycode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bi+Zc38QxKhN4vHv8pIoHUoniwMaI51nVvZ49nGDU+M=";
  };

  npmDepsHash = "sha256-glF7AivoWjkRSwKWIkixJvLVn4uN8DpU+bsGg4VqcaU=";

  # The optional `cloudflared` npm dep is a stub whose install script downloads
  # the real binary from github — no good in a sandbox. host.js already falls
  # back to a `cloudflared` on PATH, which is what the wrapper below supplies.
  npmFlags = ["--omit=optional"];

  # Nothing to build at the package level; node-pty's addon is compiled by its
  # own install script during `npm ci` (nodejs.python comes with the builder).
  dontNpmBuild = true;

  nativeBuildInputs = [makeWrapper];

  # host.js resolves the agent to share with `which <agent>` and refuses to
  # start if that lookup fails, so `which` is a runtime dep, not just a test one.
  nativeCheckInputs = [which];

  # Upstream's updater is `git pull && npm i` in the install dir, which here is
  # an immutable store path — it would fail with a misleading "are you online?".
  postPatch = ''
    cp ${./update-stub.js} lib/update.js
  '';

  # Worth the ~40s: the suites host a real bash session and join it back over
  # ws (direct, through the relay, browser page, chat, secret masking), so they
  # exercise the node-pty addon this build compiles rather than just importing
  # it. buildNpmPackage ships no check hook, hence the explicit phase; $HOME is
  # /homeless-shelter in the sandbox and the host writes session state there.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME=$(mktemp -d)
    node test/smoke.js
    node test/edges.js
    runHook postCheck
  '';

  postInstall = ''
    for b in manycode ccshare; do
      wrapProgram $out/bin/$b --suffix PATH : ${lib.makeBinPath [cloudflared which]}
    done
  '';

  passthru.updateScript = nix-update-script {};

  meta = {
    description = "Share a live coding-agent terminal session with a join code";
    homepage = "https://github.com/unworld11/manycode";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "manycode";
  };
})
