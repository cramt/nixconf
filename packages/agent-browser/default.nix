{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  nix-update-script,
  ungoogled-chromium,
  # The browser agent-browser drives via CDP. Overridable so a host can swap in
  # google-chrome etc.; defaults to the chromium that's already in our closure.
  chromium ? ungoogled-chromium,
}:
# Vercel's agent-browser — a fast native-Rust browser-automation CLI for AI
# agents (https://github.com/vercel-labs/agent-browser). Ships as an npm tarball
# with all platform binaries baked into bin/ plus a `skill-data/` tree the CLI
# serves via `agent-browser skills get <name>`. We pull the tarball, patchelf the
# glibc binary for our platform, and wire two env vars so it needs no `agent-
# browser install` step (which would download a Chrome-for-Testing build that
# won't run on NixOS): the skills dir and the Chromium executable path.
#
# Bump: set version, then
#   nix-prefetch-url --type sha256 \
#     "https://registry.npmjs.org/agent-browser/-/agent-browser-<VERSION>.tgz" \
#     | xargs nix hash to-sri --type sha256
let
  version = "0.31.1";
  binaryName =
    {
      x86_64-linux = "agent-browser-linux-x64";
      aarch64-linux = "agent-browser-linux-arm64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "agent-browser: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "agent-browser";
    inherit version;

    src = fetchurl {
      url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
      hash = "sha256-pJX3pbnHVg0ZEJr55xMAzKJSlwY4cOUhlEMpFpVBQh4=";
    };

    nativeBuildInputs = [autoPatchelfHook makeWrapper];
    buildInputs = [stdenv.cc.cc.lib];

    dontConfigure = true;
    dontBuild = true;

    # The tarball's single top-level `package/` dir is auto-stripped, so we're
    # already inside it. Keep the native binary unwrapped under libexec and the
    # skill content + Claude-skill stub under share; wrap the binary so it always
    # sees its skills dir and a working Chromium regardless of the caller's env.
    installPhase = ''
      runHook preInstall

      install -Dm755 "bin/${binaryName}" "$out/libexec/agent-browser"
      mkdir -p "$out/share/agent-browser"
      cp -r skill-data "$out/share/agent-browser-skill-data"
      cp -r skills "$out/share/agent-browser/skills"

      makeWrapper "$out/libexec/agent-browser" "$out/bin/agent-browser" \
        --set-default AGENT_BROWSER_SKILLS_DIR "$out/share/agent-browser-skill-data" \
        --set-default AGENT_BROWSER_EXECUTABLE_PATH "${chromium}/bin/chromium"

      runHook postInstall
    '';

    # Expose the ready-to-symlink Claude Code skill dir for consumers.
    passthru.skillsDir = "share/agent-browser/skills";

    # nix-update tracks the latest release tag off the GitHub homepage and
    # rewrites the versioned npm tarball URL + hash.
    passthru.updateScript = nix-update-script {};

    meta = {
      description = "Vercel agent-browser — fast browser-automation CLI for AI agents";
      homepage = "https://github.com/vercel-labs/agent-browser";
      license = lib.licenses.asl20;
      platforms = ["x86_64-linux" "aarch64-linux"];
      mainProgram = "agent-browser";
    };
  }
