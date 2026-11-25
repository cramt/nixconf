# APKs from the Nix store, which Nixup itself can't install: its app lists only
# take repositories, release pages and Google Play. For packaged APKs, chiefly
# my-nixpkgs' revanced-magisk-module, which tracks j-hc's CI there instead of on
# the phone:
#
#   myNixup.apks."com.reddit.frontpage" = pkgs.revanced-magisk-module.apps.reddit.apk;
#
# The phone fetches each APK from cramt.cachix.org like any other store path
# (my-nixpkgs' CI pushes them there), and a unit installs whichever one isn't
# installed yet, or changed since the last build.
{ inputs, ... }:
{
  nixupModules.apks = { config, lib, pkgs, ... }:
    let
      apks = config.myNixup.apks;
      state = "/var/lib/install-apks";
    in
    {
      options.myNixup.apks = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = { };
        description = "APK files to install, by the package name each installs as.";
      };

      config = lib.mkMerge [
        {
          # my-nixpkgs' packages, as hosts have them (overlays/default.nix).
          nixpkgs.overlays = [ inputs.my-nixpkgs.overlays.default ];
          nix.settings = {
            substituters = [ "https://cramt.cachix.org" ];
            trusted-public-keys = [ "cramt.cachix.org-1:F7DlWw50o0gCn5TxMuep2PPku+7L9dxTIarTnPaNvls=" ];
          };

          # Nixup 0.1.16 fetches a build's packages with NIX_CONF_DIR pointed at its own
          # nix.conf (module/common.sh nix_conf), so nix.settings.substituters never
          # reaches the fetch and nothing from cachix comes down. Nix still reads the
          # user config under that HOME, so this puts them there for every later build.
          # The very first build on a phone needs it written by hand once.
          # Remove once Nixup's fetch reads the config's substituters.
          systemd.services.nixup-fetch-caches = {
            description = "nix.settings caches for Nixup's own package fetch";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = let s = config.nix.settings; in ''
              mkdir -p /data/adb/nixup/home/.config/nix
              cat > /data/adb/nixup/home/.config/nix/nix.conf <<'EOF'
              extra-substituters = ${lib.concatStringsSep " " s.substituters}
              extra-trusted-public-keys = ${lib.concatStringsSep " " s.trusted-public-keys}
              EOF
            '';
          };
        }

        (lib.mkIf (apks != { }) {
          # android.strict would hide them, as no app list names them.
          android.strict.keep = lib.attrNames apks;

          systemd.services.install-apks = {
            description = "Install myNixup.apks";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              StateDirectory = "install-apks";
            };
            # pm hands the file to Android's package manager, which can't see
            # Nixup's /nix, so the APK goes over stdin the way adb install
            # streams one. Through a pipe, not a redirect: SELinux won't let
            # system_server read an fd of the store's adb_data_file ("Failed
            # transaction"). The stamp is the store path last installed: a new
            # build reinstalls, an app removed by hand comes back.
            # One that fails (stock Reddit still installed: another signer)
            # doesn't hold up the rest; the unit fails after them.
            script = ''
              failed=
            '' + lib.concatStrings (lib.mapAttrsToList (name: apk: ''
              if [ "$(cat ${state}/${name} 2>/dev/null)" != ${apk} ] || [ -z "$(pm path ${name} 2>/dev/null)" ]; then
                echo "installing ${name} from ${apk}"
                if cat ${apk} | pm install -r -S "$(stat -c %s ${apk})"; then
                  echo ${apk} > ${state}/${name}
                else
                  failed="$failed ${name}"
                fi
              fi
            '') apks) + ''
              [ -z "$failed" ] || { echo "not installed:$failed" >&2; exit 1; }
            '';
          };
        })
      ];
    };
}
