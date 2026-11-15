# Distributed builds across whichever fleet machines are switched on. Members
# are the hosts whose host.nix sets `builder` (see modules/flake/hosts.nix);
# each one serves builds to the others and offloads to them in turn, so it
# doesn't matter which machine `just deploy` runs from. Felix builds locally
# while a local max-jobs slot is free and only offloads the overflow (stock
# Lix never builds locally while a matching remote exists).
{ ... }: {
  flake.nixosModules."networking.build-pool" = { lib, pkgs, hostDir, buildPool, ... }:
    let
      self = baseNameOf hostDir;
      peers = lib.filterAttrs (name: _: name != self) buildPool;
      machinesFile = "/run/build-pool/machines";
      # Same on every member, since peers dial each other's.
      loadPort = 38780;

      # Rendered inside the probe's double quotes: $slots is filled in per run.
      machineLine = peer: lib.concatStringsSep " " [
        "ssh-ng://nix-ssh@${peer.address}"
        (lib.concatStringsSep "," peer.systems)
        "/etc/ssh/ssh_host_ed25519_key"
        "$slots"
        (toString peer.speedFactor)
        (lib.concatStringsSep "," peer.features)
        "-"
      ];
    in
    {
      config = lib.mkIf (buildPool ? ${self}) {
        nix.sshServe = {
          enable = true;
          protocol = "ssh-ng";
          write = true;
          # Untrusted, the daemon refuses the peer's unsigned build inputs.
          trusted = true;
          keys = lib.mapAttrsToList (_: peer: peer.hostKey) peers;
        };

        programs.ssh.knownHosts = lib.mapAttrs (_: peer: {
          hostNames = [ peer.address ];
          publicKey = peer.hostKey;
        }) peers;

        # Without distributedBuilds the nixpkgs module forces `builders` to null.
        nix.distributedBuilds = true;
        nix.settings = {
          builders = "@${machinesFile}";
          # Builders fetch cached deps themselves instead of us uploading them.
          builders-use-substitutes = true;
        };

        # The build hook only counts the slots *this* client holds, so it
        # can't tell a peer busy with its own work (luna streaming, another
        # client's builds) from an idle one. Each member answers with its
        # 1-minute load and core count; tailscale0 is a trusted interface, so
        # this is reachable over the tailnet and nowhere the firewall guards.
        port-selector.set-ports.${toString loadPort} = "build_pool_load";
        systemd.sockets.build-pool-load = {
          wantedBy = [ "sockets.target" ];
          listenStreams = [ (toString loadPort) ];
          socketConfig.Accept = true;
        };
        systemd.services."build-pool-load@" = {
          description = "Report load and core count to a build pool peer";
          path = [ pkgs.coreutils ];
          script = ''
            read -r load _ < /proc/loadavg
            echo "$load $(nproc)"
          '';
          serviceConfig = {
            StandardInput = "socket";
            StandardOutput = "socket";
            DynamicUser = true;
          };
        };

        # Lix's build hook re-reads the machine list for every derivation and
        # only skips a dead builder for that one derivation, so a static list
        # with a powered-off peer costs a connect timeout per uncached build.
        # Listing only the peers that answer right now makes offline ones free.
        #
        # Each peer gets maxJobs scaled by its idle fraction, rounded:
        # luna (8 cores, maxJobs 2) keeps both slots under load 2, one under
        # load 6, and drops out entirely past that until it calms down. A peer
        # that's up but doesn't answer on loadPort (not yet deployed with it)
        # keeps its full maxJobs.
        systemd.services.build-pool-probe = {
          description = "List the reachable, not-overloaded build pool peers for the nix daemon";
          path = [ pkgs.coreutils pkgs.bash pkgs.gawk ];
          serviceConfig = {
            Type = "oneshot";
            RuntimeDirectory = "build-pool";
            RuntimeDirectoryPreserve = true;
          };
          script = ''
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            ${lib.concatStrings (lib.mapAttrsToList (name: peer: ''
              (
                timeout 2 bash -c '</dev/tcp/${peer.address}/22' 2>/dev/null || exit 0
                slots=${toString peer.maxJobs}
                if reply=$(timeout 2 bash -c 'exec 3<>/dev/tcp/${peer.address}/${toString loadPort}; cat <&3' 2>/dev/null) \
                    && [ -n "$reply" ]; then
                  slots=$(awk -v m=${toString peer.maxJobs} '{ s = int(m * ($2 - $1) / $2 + 0.5); print (s < 0 ? 0 : s) }' <<<"$reply")
                fi
                [ "$slots" -gt 0 ] || exit 0
                echo "${machineLine peer}" > "$tmp/${name}"
              ) &
            '') peers)}
            wait
            cat "$tmp"/* > ${machinesFile}.new 2>/dev/null || : > ${machinesFile}.new
            mv ${machinesFile}.new ${machinesFile}
          '';
        };
        systemd.timers.build-pool-probe = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnActiveSec = "0";
            OnUnitActiveSec = "15s";
            AccuracySec = "1s";
          };
        };
      };
    };
}
