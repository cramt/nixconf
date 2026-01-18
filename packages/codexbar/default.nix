# codexbarcli.nix
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:
stdenv.mkDerivation rec {
  pname = "codexbarcli";
  version = "0.17.0"; # update to actual version

  src = fetchurl {
    url = "https://github.com/steipete/CodexBar/releases/download/v${version}/CodexBarCLI-v${version}-linux-x86_64.tar.gz";
    sha256 = "sha256-m/m7b70z7Ro8I3Z+na2IATGPZyLoaqoEN0AKN8Er+90=";
  };

  nativeBuildInputs = [autoPatchelfHook makeWrapper];
  buildInputs = [];

  unpackPhase = "tar -xzvf $src";
  installPhase = ''
    mkdir -p $out/bin
    cp -v CodexBarCLI $out/bin/codexbarcli
    chmod +x $out/bin/codexbarcli

    makeWrapper $out/bin/codexbarcli $out/bin/codexbarcli \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath buildInputs}
  '';

  dontStrip = true;
}
