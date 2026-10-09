# Distributed builds across whichever fleet machines are switched on. Members
# are the hosts whose host.nix sets `builder` (see modules/flake/hosts.nix);
# each one serves builds to the others and offloads to them in turn, so it
# doesn't matter which machine `just deploy` runs from.
{ ... }: {
  flake.nixosModules."networking.build-pool" = { lib, pkgs, hostDir, buildPool, ... }:
    let
      self = baseNameOf hostDir;
      peers = lib.filterAttrs (name: _: name != self) buildPool;
      machinesFile = "/run/build-pool/machines";

      machineLine = peer: lib.concatStringsSep " " [
        "ssh-ng://nix-ssh@${peer.address}"
        (lib.concatStringsSep "," peer.systems)
        "/etc/ssh/ssh_host_ed25519_key"
        (toString peer.maxJobs)
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

        # Lix's build hook re-reads the machine list for every derivation and
        # only skips a dead builder for that one derivation, so a static list
        # with a powered-off peer costs a connect timeout per uncached build.
        # Listing only the peers that answer right now makes offline ones free.
        systemd.services.build-pool-probe = {
          description = "List the reachable build pool peers for the nix daemon";
          path = [ pkgs.coreutils pkgs.bash ];
          serviceConfig = {
            Type = "oneshot";
            RuntimeDirectory = "build-pool";
            RuntimeDirectoryPreserve = true;
          };
          script = ''
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            ${lib.concatStrings (lib.mapAttrsToList (name: peer: ''
              ( timeout 2 bash -c '</dev/tcp/${peer.address}/22' 2>/dev/null \
                  && echo ${lib.escapeShellArg (machineLine peer)} > "$tmp/${name}" ) &
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
