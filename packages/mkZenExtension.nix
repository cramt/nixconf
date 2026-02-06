{pkgs, ...}: {
  name,
  js,
  shortcut ? null,
  description ? name,
  permissions ? [],
  version ? "1.0.0",
}: let
  addonId = "${name}@zen.custom";

  backgroundJs =
    if shortcut != null
    then ''
      browser.commands.onCommand.addListener((command) => {
        if (command === "${name}") {
          ${js}
        }
      });
    ''
    else js;

  manifest = builtins.toJSON ({
      manifest_version = 2;
      inherit name version description;
      browser_specific_settings.gecko.id = addonId;
      inherit permissions;
      background.scripts = ["background.js"];
    }
    // (
      if shortcut != null
      then {
        commands.${name} = {
          suggested_key.default = shortcut;
          inherit description;
        };
      }
      else {}
    ));
in
  pkgs.stdenv.mkDerivation {
    pname = name;
    inherit version;
    dontUnpack = true;
    nativeBuildInputs = [pkgs.zip];
    buildPhase = ''
      mkdir ext
      cp ${pkgs.writeText "manifest.json" manifest} ext/manifest.json
      cp ${pkgs.writeText "background.js" backgroundJs} ext/background.js
      cd ext && zip -r ../addon.xpi . && cd ..
    '';
    installPhase = ''
      mkdir -p "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
      cp addon.xpi "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${addonId}.xpi"
    '';
    passthru = {inherit addonId;};
  }
