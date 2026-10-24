{...}: {
  flake.nixosModules."services.koblet" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.koblet;
    configFile = "${cfg.stateDir}/.config/koblet/config.json";
    bin = "${cfg.stateDir}/bin/koblet";
    # Shown at enrollment as "plain boxes" until koblet can reach its own user
    # manager: it runs boxfsd as a `systemctl --user` unit, and a system
    # service doesn't inherit the address of that bus.
    run = pkgs.writeShellScript "koblet-run" ''
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      # Lingering starts user@ in parallel with us at boot; koblet only probes
      # for it once, at startup.
      for _ in $(seq 30); do
        [ -S "$XDG_RUNTIME_DIR/bus" ] && break
        sleep 1
      done
      exec "${bin}" run
    '';
    # Only koblet-linux-x86_64 is published as of 2026-10-24; aarch64 404s.
    url = "${cfg.server}/runner/dist/koblet-linux-${pkgs.stdenv.hostPlatform.uname.processor}";

    # Kobl ships one rolling binary, so pinning it in the store would just mean
    # chasing a hash. Instead every start pulls the latest one, then koblet keeps
    # itself current from there. A failed fetch (network not up yet) falls back
    # to whatever we already have rather than keeping the runner down.
    prestart = pkgs.writeShellApplication {
      name = "koblet-prestart";
      runtimeInputs = with pkgs; [coreutils curl];
      text = ''
        mkdir -p "${cfg.stateDir}/bin"
        tmp=$(mktemp "${bin}.XXXXXX")
        trap 'rm -f "$tmp"' EXIT

        if curl --fail --silent --show-error "${url}" -o "$tmp" \
          && expected=$(curl --fail --silent --show-error "${url}.sha256") \
          && actual=$(sha256sum "$tmp") \
          && [ "''${actual%% *}" = "''${expected%% *}" ]; then
          chmod 0755 "$tmp"
          mv "$tmp" "${bin}"
        elif [ -x "${bin}" ]; then
          echo "koblet fetch failed, running the existing binary" >&2
        else
          echo "koblet fetch failed and nothing is installed yet" >&2
          exit 1
        fi

        # The code is one-time: it buys config.json, which is the real credential.
        if [ ! -e "${configFile}" ]; then
          "${bin}" enroll --server "${cfg.server}" \
            "$(cat ${config.services.onepassword-secrets.secretPaths.koblEnrollCode})"
        fi
      '';
    };
  in {
    options.myNixOS.services.koblet = {
      enable = lib.mkEnableOption "myNixOS.services.koblet (Kobl host runner)";
      server = lib.mkOption {
        type = lib.types.str;
        default = "https://bearcove.kobl.it";
      };
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/koblet";
        description = "koblet's home: the self-updating binary, its credential, and whatever jobs leave behind.";
      };
      enrollCode = lib.mkOption {
        type = lib.types.str;
        default = "op://Homelab/Kobl/enrollCode";
        description = "1Password reference to a one-time code from Kobl → Settings → Hosts. Only read while the host is not enrolled yet.";
      };
    };

    config = lib.mkIf cfg.enable {
      # koblet is a generic glibc binary.
      programs.nix-ld.enable = true;

      services.onepassword-secrets.secrets.koblEnrollCode = {
        reference = cfg.enrollCode;
        owner = "koblet";
        group = "koblet";
        mode = "0400";
        services = ["koblet"];
      };

      users.groups.koblet = {};
      users.users.koblet = {
        isSystemUser = true;
        group = "koblet";
        home = cfg.stateDir;
        # koblet reads the job environment from `$SHELL -l -i`, which nologin can't serve.
        shell = pkgs.bashInteractive;
        # Boxes: a user manager for boxfsd, and subuids for rootless podman.
        linger = true;
        autoSubUidGidRange = true;
        # A starting toolset for jobs, not a sandbox. It goes in the user's
        # profile rather than the unit's path: koblet takes the job environment
        # from `$SHELL -l -i`, and boxfsd runs under the user manager, and both
        # see /etc/profiles/per-user/koblet but neither sees the unit's PATH.
        # koblet probes for python3 >= 3.11 specifically.
        packages = with pkgs; [bashInteractive coreutils git python3];
      };

      virtualisation.podman.enable = true;
      # boxfs mounts each box's root over FUSE, which needs the setuid fusermount3.
      programs.fuse = {
        enable = true;
        # So a box's own (subuid) users reach the files of the boxfs mount koblet owns.
        userAllowOther = true;
      };

      systemd.tmpfiles.rules = ["d ${cfg.stateDir} 0700 koblet koblet -"];

      systemd.services.koblet = {
        description = "Kobl host runner";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];

        path = config.users.users.koblet.packages ++ [config.virtualisation.podman.package pkgs.fuse3 "/run/wrappers"];

        environment = {
          HOME = cfg.stateDir;
          XDG_CONFIG_HOME = "${cfg.stateDir}/.config";
          SHELL = lib.getExe pkgs.bashInteractive;
        };

        # koblet only checks whether this host can run boxes once, at startup.
        restartTriggers = [config.environment.etc."fuse.conf".text];

        unitConfig.RequiresMountsFor = [cfg.stateDir];

        serviceConfig = {
          User = "koblet";
          Group = "koblet";
          ExecStartPre = lib.getExe prestart;
          ExecStart = run;
          Restart = "always";
          RestartSec = 5;
          UMask = "0077";
        };
      };
    };
  };
}
