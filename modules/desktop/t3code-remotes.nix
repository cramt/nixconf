# T3 Code desktop app: saved connections to our own servers, so a desktop comes
# up already paired with luna instead of someone pasting the secret into the
# pairing screen on every machine.
#
# The app has no config file, env var or deep link for this. Its connection
# list lives in ~/.t3/userdata/connection-catalog.json, encrypted with Electron
# safeStorage, which on Linux is Chromium's os_crypt "v11": AES-128-CBC, key =
# PBKDF2-SHA1(password from the keyring item for app "T3 Code (Alpha)", salt
# "saltysalt", 1 iteration), IV of 16 spaces. A user unit at login decrypts it,
# upserts each declared server and re-encrypts, so everything else in there
# (learned LAN routes, servers added by hand) stays UI-owned.
#
# The stored credential is the server's shared secret itself
# (myNixOS.services.t3code.sharedSecret): the server takes it as a bearer
# token, so no pairing round-trip is needed.
#
# A host that also runs the background server (myNixOS.services.t3code) can't
# give the app ~/.t3: the server holds a lock on it and the app quits with
# "This T3 home is unavailable". The app gets its own T3CODE_HOME there, and the
# local server is added as one more connection, like luna.
{ ... }: {
  flake.nixosModules."desktop.t3code-remotes" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.t3code-remotes;
    localServer = config.myNixOS.services.t3code;
    sharesHome = localServer.enable && localServer.user == cfg.user;
    appHome = "/home/${cfg.user}/${if sharesHome then ".t3-desktop" else ".t3"}";
    # opnix only takes camelCase keys.
    secretName = name: "t3codeRemote${lib.toUpper (lib.substring 0 1 name)}${lib.substring 1 (-1) name}";
    catalogEntries = lib.mapAttrsToList (name: r: {
      inherit (r) environmentId label;
      url = lib.removeSuffix "/" r.url;
      secretPath = config.services.onepassword-secrets.secretPaths.${secretName name};
    }) cfg.servers
    # The server mints its environment id on first start, so it's read off
    # disk at sync time rather than declared.
    ++ lib.optional sharesHome {
      label = config.networking.hostName;
      url = "http://127.0.0.1:${toString config.port-selector.ports.t3code}";
      environmentIdFile = "/home/${localServer.user}/.t3/userdata/environment-id";
      secretPath = config.services.onepassword-secrets.secretPaths.t3codeSharedSecret;
    };
    entriesFile = (pkgs.formats.json {}).generate "t3code-remotes.json" catalogEntries;
    sync = pkgs.writeShellApplication {
      name = "t3code-remotes-sync";
      runtimeInputs = [pkgs.coreutils pkgs.jq pkgs.openssl pkgs.libsecret pkgs.procps];
      text = ''
        app="T3 Code (Alpha)"
        dir="${appHome}/userdata"
        catalog="$dir/connection-catalog.json"

        # The app holds the catalog in memory and writes it back, so an edit
        # made under a running app would be lost. Next login picks it up.
        if pgrep -u "$(id -u)" -f 't3code-.*-desktop/' >/dev/null; then
          echo "T3 Code is running, leaving its catalog alone"
          exit 0
        fi

        # The app creates this item on first launch. Creating it here instead
        # lets a fresh machine get its servers before the app ever ran.
        if ! pw=$(secret-tool lookup application "$app") || [ -z "$pw" ]; then
          openssl rand -base64 16 | tr -d '\n' \
            | secret-tool store --label "Chromium Safe Storage" \
                xdg:schema chrome_libsecret_os_crypt_password_v2 application "$app"
          pw=$(secret-tool lookup application "$app")
        fi
        key=$(openssl kdf -keylen 16 -kdfopt digest:SHA1 -kdfopt pass:"$pw" \
          -kdfopt salt:saltysalt -kdfopt iter:1 PBKDF2 | tr -d :)
        iv=20202020202020202020202020202020

        current='{"schemaVersion":1,"targets":[],"profiles":[],"credentials":[],"remoteDpopTokens":[],"disabledEnvironmentIds":[]}'
        if [ -s "$catalog" ]; then
          current=$(jq -r .encryptedCatalog "$catalog" | base64 -d | tail -c +4 \
            | openssl enc -d -aes-128-cbc -K "$key" -iv "$iv")
        fi

        # Secrets are read into jq here, never onto a command line.
        entries=$(jq -c '.[]' ${entriesFile} | while read -r e; do
          id=$(jq -r '.environmentId // empty' <<<"$e")
          if [ -z "$id" ]; then
            idFile=$(jq -r .environmentIdFile <<<"$e")
            if [ ! -s "$idFile" ]; then
              echo "$idFile missing, the server hasn't started yet; skipping $(jq -r .label <<<"$e")"
              continue
            fi
            id=$(tr -d '[:space:]' < "$idFile")
          fi
          jq -c --arg id "$id" --rawfile token "$(jq -r .secretPath <<<"$e")" \
            '. + {environmentId: $id, token: ($token | rtrimstr("\n")), connectionId: "bearer:\($id):\(.url)"}' <<<"$e"
        done | jq -s .)

        updated=$(jq -c --argjson entries "$entries" '
          ($entries | map(.connectionId)) as $ids
          | .targets |= (map(select(.connectionId as $c | $ids | index($c) | not)) + ($entries | map({
              _tag: "BearerConnectionTarget", environmentId, label, connectionId})))
          | .profiles |= (map(select(.connectionId as $c | $ids | index($c) | not)) + ($entries | map({
              _tag: "BearerConnectionProfile", connectionId, environmentId, label,
              httpBaseUrl: "\(.url)/", wsBaseUrl: "\(.url | sub("^http"; "ws"))/"})))
          | .credentials |= (map(select(.connectionId as $c | $ids | index($c) | not)) + ($entries | map({
              connectionId, credential: {_tag: "BearerConnectionCredential", token}})))
        ' <<<"$current")

        install -d -m700 "$dir"
        umask 077
        encrypted=$( { printf v11; printf '%s' "$updated" \
          | openssl enc -aes-128-cbc -K "$key" -iv "$iv"; } | base64 -w0)
        jq -n --arg c "$encrypted" '{version: 1, encryptedCatalog: $c}' > "$catalog.new"
        mv "$catalog.new" "$catalog"
      '';
    };
  in {
    options.myNixOS.t3code-remotes = {
      enable = lib.mkEnableOption "myNixOS.t3code-remotes";
      user = lib.mkOption {
        type = lib.types.str;
        default = "cramt";
        description = "Desktop user whose T3 Code app gets the connections.";
      };
      servers = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options = {
            label = lib.mkOption {
              type = lib.types.str;
              default = name;
            };
            url = lib.mkOption {
              type = lib.types.str;
              example = "https://t3.cramt.dk";
            };
            environmentId = lib.mkOption {
              type = lib.types.str;
              description = ''
                The server's ~/.t3/userdata/environment-id. The app keys
                connections by it, so a wrong one shows as a second,
                never-connecting server.
              '';
            };
            sharedSecret = lib.mkOption {
              type = lib.types.str;
              description = "1Password reference to the server's myNixOS.services.t3code.sharedSecret.";
            };
          };
        }));
        default = {
          luna = {
            url = "https://t3.cramt.dk";
            environmentId = "cbfdcf3a-5b4a-48b3-a0a5-32204601a282";
            sharedSecret = "op://Homelab/T3Code/password";
          };
        };
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [{
        assertion = sharesHome -> localServer.sharedSecret != null;
        message = "myNixOS.t3code-remotes adds this host's own t3code server as a connection, which needs myNixOS.services.t3code.sharedSecret.";
      }];

      services.onepassword-secrets.secrets = lib.mapAttrs' (name: r:
        lib.nameValuePair (secretName name) {
          reference = r.sharedSecret;
          owner = cfg.user;
          mode = "0400";
        }) cfg.servers;

      home-manager.users.${cfg.user} = { ... }: {
        nixpkgs.overlays = lib.optional sharesHome (final: prev: {
          t3code-desktop = prev.symlinkJoin {
            inherit (prev.t3code-desktop) name meta;
            paths = [prev.t3code-desktop];
            nativeBuildInputs = [final.makeWrapper];
            postBuild = "wrapProgram $out/bin/t3code-desktop --set T3CODE_HOME ${appHome}";
          };
        });
        systemd.user.services.t3code-remotes = {
          Unit = {
            Description = "Add our T3 Code servers to the desktop app's connections";
            # The keyring has to be unlocked, which the login session does.
            After = ["graphical-session.target"];
            PartOf = ["graphical-session.target"];
          };
          Install.WantedBy = ["graphical-session.target"];
          Service = {
            Type = "oneshot";
            ExecStart = "${sync}/bin/t3code-remotes-sync";
          };
        };
      };
    };
  };
}
