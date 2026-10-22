{
  stdenvNoCC,
  fetchurl,
}:
# cli-proxy-api's web control panel: upstream ships it prebuilt as a single
# self-contained management.html per release. Fetched from the tagged release
# rather than /releases/latest/download, whose content moves under any lock
# every time upstream cuts a release (every 1-3 days) and broke eval with a NAR
# hash mismatch. `just update_packages` bumps it via nix-update.
#
# A directory, because MANAGEMENT_STATIC_PATH wants either a file literally
# named management.html or a directory containing one.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cli-proxy-api-panel";
  version = "1.26.7";

  src = fetchurl {
    url = "https://github.com/router-for-me/Cli-Proxy-API-Management-Center/releases/download/v${finalAttrs.version}/management.html";
    hash = "sha256-jJxrfT+zEeaq1dBuGZPlOi0oOJ5kBEihvGME7SCwV7U=";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm644 $src $out/management.html
  '';
})
