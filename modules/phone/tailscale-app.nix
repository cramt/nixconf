# Tailscale's Android app beside fleet.nix's root tailscaled, which is userspace
# only: the way into the phone, never a route out for its apps. The app owns
# Android's VPN slot, so apps (T3 Code) reach the tailnet through it. It joins
# as its own node, <hostName>-vpn, tagged like the rest of the fleet.
#
# Nothing to tap: the APK comes from my-nixpkgs through myNixup.apks, and a unit
# enrolls it the way an MDM would. It mints a one-off preauthorized auth key with
# the fleet's OAuth client (the app's AuthKey policy takes no tags, so the client
# secret itself won't do), writes it into the app's managed restrictions
# (/data/system/users/0/res_<package>.xml, what RestrictionsManager reads), and
# grants the VPN consent dialog's appop. It enrolls once per install of the app:
# reinstalling it (or deleting the stamp) enrolls it again.
{ ... }:
{
  nixupModules.tailscaleApp = { config, lib, pkgs, ... }:
    let
      cfg = config.myNixup.tailscaleApp;
      app = pkgs.tailscale-android;
      package = app.packageName;
      state = "/var/lib/tailscale-app";
      restrictions = "/data/system/users/0/res_${package}.xml";
    in
    {
      options.myNixup.tailscaleApp = {
        enable = lib.mkEnableOption "Tailscale's Android app, enrolled in the fleet tailnet" // { default = true; };
        hostname = lib.mkOption {
          type = lib.types.str;
          default = "${config.networking.hostName}-vpn";
          description = "The app's node name; the phone's own name is the root tailscaled's.";
        };
      };

      config = lib.mkIf cfg.enable {
        myNixup.apks.${package} = app;

        # Android starts and keeps the tunnel itself, from boot on. Without it the
        # app sits in the background with the screen off, where Android 15+ cuts
        # its network (blocked=APP_BACKGROUND) before it ever opens the VPN.
        # ConnectivityService reads these at boot, so a first switch needs one.
        android.settings.raw.secure = {
          always_on_vpn_app = package;
          always_on_vpn_lockdown = 0;
        };
        myNixup.secrets.tailscaleNodeKey.services = [ "tailscale-app-enroll" ];

        systemd.services.tailscale-app-enroll = {
          description = "Enroll Tailscale's app in the fleet tailnet";
          wantedBy = [ "multi-user.target" ];
          after = [ "install-apks.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "tailscale-app";
          };
          path = with pkgs; [ curl jq ];
          environment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          script = ''
            installed=$(dumpsys package ${package} | sed -n 's/^ *firstInstallTime=//p' | head -1)
            [ -n "$installed" ] || { echo "${package} is not installed" >&2; exit 1; }
            # Out of battery optimisation, so Doze never takes the tunnel's network.
            dumpsys deviceidle whitelist +${package} > /dev/null
            if [ "$(cat ${state}/enrolled 2>/dev/null)" = "$installed" ]; then
              echo "enrolled already (installed $installed)"
              exit 0
            fi

            # The API takes the client secret alone; client_id is ignored.
            token=$(curl -fsS https://api.tailscale.com/api/v2/oauth/token -d client_id=fleet \
              --data-urlencode "client_secret=$(cat ${config.myNixup.secrets.tailscaleNodeKey.path})" \
              | jq -er .access_token)
            key=$(curl -fsS -H "Authorization: Bearer $token" https://api.tailscale.com/api/v2/tailnet/-/keys \
              -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["tag:fleet"]}}},"expirySeconds":3600,"description":"${cfg.hostname} app enrollment"}' \
              | jq -er .key)

            cat > ${restrictions} <<EOF
            <?xml version='1.0' encoding='utf-8' standalone='yes' ?>
            <restrictions>
            <entry key="AuthKey" type="s">$key</entry>
            <entry key="Hostname" type="s">${cfg.hostname}</entry>
            <entry key="ForceEnabled" type="b">true</entry>
            <entry key="OnboardingFlow" type="s">hide</entry>
            </restrictions>
            EOF
            # Android's system user, by number: Nixup's /etc/passwd doesn't name it.
            chown 1000:1000 ${restrictions}
            chmod 600 ${restrictions}
            # Android's toybox: Nix's coreutils is built without SELinux.
            /system/bin/chcon u:object_r:system_data_file:s0 ${restrictions}

            # The "connection request" dialog Android shows before an app's first VPN.
            appops set ${package} ACTIVATE_VPN allow
            # The app reads its policies at start.
            am force-stop ${package}
            am start -n ${package}/.MainActivity > /dev/null

            echo "$installed" > ${state}/enrolled
            echo "enrolled as ${cfg.hostname}"
          '';
        };
      };
    };
}
