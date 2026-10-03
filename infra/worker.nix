# A Cloudflare worker bundled by wrangler, in the sandbox. Same lockfile and
# same wrangler as a local `wrangler deploy --dry-run`, so the output is
# byte-identical to what that would upload.
{ pkgs, name, hash }:
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "${name}-worker";
  version = "0";
  src = ./${name};
  nativeBuildInputs = [ pkgs.nodejs pkgs.pnpm_10 pkgs.pnpmConfigHook ];
  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pkgs.pnpm_10;
    fetcherVersion = 3;
    inherit hash;
  };
  buildPhase = ''
    export HOME=$TMPDIR WRANGLER_SEND_METRICS=false
    pnpm exec wrangler deploy --dry-run --outdir dist --minify
  '';
  installPhase = "cp dist/index.js $out";
})
