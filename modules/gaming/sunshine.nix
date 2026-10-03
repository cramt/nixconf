# Sunshine: this host is the gaming desktop that ganymede's Moonlight streams
# games from (cramt/emrakul, "Gaming desktop" in its CONTEXT.md).
#
# It runs as nixpkgs' user service, hung off graphical-session.target, so it
# only exists while someone is logged in graphically. Getting it up with nobody
# at the desk means autologin, and getting woken by Moonlight means suspending
# instead of powering off; both change how the daily desktop behaves, so they
# are host decisions and deliberately not made here.
#
# Everything the web UI would otherwise hold is declared, so it has nothing
# left to set up:
# - settings and apps, which locks its config pages;
# - the pairing: moonlight-pairing.json (from `nix run .#moonlight-pairing`)
#   names the clients and this host's cert, its key comes from 1Password;
# - the web UI login, from the same 1Password item.
{...}: {
  flake.nixosModules."features.sunshine" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.sunshine;
    pairing = lib.importJSON ./moonlight-pairing.json;
    secretPaths = config.services.onepassword-secrets.secretPaths;
    item = "op://Homelab/Sunshine-${config.networking.hostName}";

    # Sunshine's paired-client store (nvhttp.cpp load_state/save_state). Only
    # certs and ids, nothing secret, so it can come from the store.
    state = pkgs.writeText "sunshine_state.json" (builtins.toJSON {
      root = {
        inherit (pairing.server) uniqueid;
        named_devices =
          lib.mapAttrsToList (name: client: {
            inherit name;
            inherit (client) uuid cert;
            enabled = true;
          })
          pairing.clients;
      };
    });

    # Sunshine reads its state and login from the config dir and writes both
    # back (a pairing or unpairing from the web UI, a changed password), so
    # they have to be writable files, not store paths. Both are put back on
    # every start: the clients in moonlight-pairing.json are the paired ones,
    # and the login is the one in 1Password. Pairing something by PIN still
    # works, but only until Sunshine restarts; declare it to keep it.
    seed = pkgs.writeShellApplication {
      name = "sunshine-seed";
      runtimeInputs = [pkgs.coreutils pkgs.jq];
      text = ''
        # Where Sunshine's relative paths resolve (platform/linux/misc.cpp
        # appdata(); nixpkgs' unit sets no CONFIGURATION_DIRECTORY).
        dir="''${XDG_CONFIG_HOME:-$HOME/.config}/sunshine"
        install -d -m 700 "$dir"
        install -m 600 ${state} "$dir/sunshine_state.json"

        # Sunshine keeps the login as username, salt and
        # hex(sha256(password + salt)), where its util::hex writes the
        # digest's bytes last to first, in upper case (httpcommon.cpp
        # save_user_creds). The password only ever goes through a pipe and
        # the environment, never an argv.
        salt=$(head -c 48 /dev/urandom | base64 -w 0 | tr -dc 'A-Za-z0-9')
        salt=''${salt:0:16}
        password=$(< ${secretPaths.sunshinePassword})
        digest=$(printf '%s%s' "$password" "$salt" | sha256sum | cut -c 1-64)
        hash=$(fold -w 2 <<< "$digest" | tac | tr -d '\n' | tr 'a-f' 'A-F')
        username=$(< ${secretPaths.sunshineUsername}) salt=$salt hash=$hash \
          jq -n '{username: env.username, salt: env.salt, password: env.hash}' \
          > "$dir/web_ui_login.json.tmp"
        chmod 600 "$dir/web_ui_login.json.tmp"
        mv "$dir/web_ui_login.json.tmp" "$dir/web_ui_login.json"
      '';
    };
  in {
    options.myNixOS.sunshine = {
      enable = lib.mkEnableOption "myNixOS.sunshine";

      user = lib.mkOption {
        type = lib.types.str;
        description = ''
          The user whose graphical session Sunshine runs in. Its secrets are
          rendered readable by that user only.
        '';
      };

      apps = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [];
        description = ''
          Sunshine apps (apps.json entries) on top of the built-in "Desktop".

          Moonlight matches them by name: `moonlight stream <host> "<name>"`.
          This is where emrakul's games get declared from the same list that
          produces ganymede's desktop entries. `image-path` takes any absolute
          .png, so a store path works for box art.
        '';
      };

      wakeOnLan.macAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2c:f0:5d:cf:62:1a";
        description = ''
          MAC of the wired NIC to arm for magic-packet Wake-on-LAN. Moonlight
          wakes the host itself before `stream`/`quit`, but only from suspend:
          a powered-off board on most NICs doesn't listen.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.services.onepassword-secrets.enable;
          message = "myNixOS.sunshine needs opnix (myNixOS.opnix-secrets) for its key and web UI login";
        }
      ];

      # The item is created by hand, see docs/moonlight-pairing.md. No `services` restart wiring: opnix restarts system units, and
      # Sunshine is a user unit. After rotating, `systemctl --user restart
      # sunshine` as the user.
      services.onepassword-secrets.secrets = let
        forUser = {
          owner = cfg.user;
          mode = "0400";
        };
      in {
        sunshineServerKey =
          forUser
          // {
            reference = "${item}/sunshine-key.pem";
            kind = "file";
          };
        sunshineUsername = forUser // {reference = "${item}/username";};
        sunshinePassword = forUser // {reference = "${item}/password";};
      };

      services.sunshine = {
        enable = true;
        openFirewall = true;
        # KMS capture reads the scanout directly, whatever the compositor. The
        # alternatives need one: wlr-screencopy is compositor-specific and the
        # portal asks for permission on screen, which nobody on the couch can
        # click. Pinned rather than auto-probed so it can't drift to those.
        capSysAdmin = true;
        settings = {
          sunshine_name = config.networking.hostName;
          capture = "kms";
          # The identity Moonlight pinned when it was seeded with the pairing.
          cert = "${pkgs.writeText "sunshine-cert.pem" pairing.server.cert}";
          pkey = secretPaths.sunshineServerKey;
          # Relative: under the config dir, where sunshine-seed writes them.
          file_state = "sunshine_state.json";
          credentials_file = "web_ui_login.json";
        };
        applications.apps =
          [
            {
              # No cmd: streams whatever is on screen. The fallback for anything
              # not declared as its own app, and the one to pair-test against.
              name = "Desktop";
              image-path = "desktop.png";
            }
          ]
          ++ cfg.apps;
      };

      systemd.user.services.sunshine.serviceConfig.ExecStartPre = lib.getExe seed;

      # Not networking.interfaces.<if>.wakeOnLan: its .link file matches on
      # OriginalName, which is the kernel's eth0, never the predictable name it
      # is given, so the policy is silently never applied.
      # https://github.com/NixOS/nixpkgs/issues/415213 — switch back once that
      # is fixed. A udev rule on the MAC also leaves 99-default.link (and with
      # it the interface's name) alone, which a matching .link file wouldn't.
      services.udev.extraRules = lib.mkIf (cfg.wakeOnLan.macAddress != null) ''
        ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="${lib.toLower cfg.wakeOnLan.macAddress}", RUN+="${lib.getExe pkgs.ethtool} -s $name wol g"
      '';
    };
  };
}
