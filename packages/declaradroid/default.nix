{
  lib,
  stdenv,
  nodejs,
  waydroid,
  apkeep,
  fdroidcl,
  unzip,
  android-tools,
  lxc,
  makeWrapper,
  waydroid-script ? null,
}:
stdenv.mkDerivation {
  pname = "declaradroid";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [makeWrapper];
  buildInputs = [nodejs];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/declaradroid
    cp -r src/* $out/lib/declaradroid/

    makeWrapper ${nodejs}/bin/node $out/bin/declaradroid \
      --add-flags "$out/lib/declaradroid/index.js" \
      --prefix PATH : ${lib.makeBinPath ([waydroid apkeep fdroidcl unzip android-tools lxc] ++ lib.optional (waydroid-script != null) waydroid-script)}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Declarative Android app management for Waydroid";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "declaradroid";
  };
}
