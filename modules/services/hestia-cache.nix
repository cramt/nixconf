# The fleet binary cache. CI's build legs push everything they build to
# ghcr.io through hestia (.github/workflows/build.yml), and luna runs hestia's
# substituter daemon against that registry for every other host. hestia only
# serves through a local HTTP daemon, never to Nix directly, hence luna.
#
# The server is whichever host site.hestia.host names, so there is no second
# switch that could disagree with where the clients point.
#
# Unsigned narinfos, so `trusted=true`: only this repo's workflows can push
# to the package (fork PRs get read-only tokens), the same people a cachix
# token trusted. The tailnet carries it, and tailscale0 is the only interface
# the ports are open on.
{inputs, ...}: let
  site = import ../../myLib/site.nix;
  h = site.hestia;
in {
  flake.nixosModules."services.hestia-cache" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.hestia-cache;
    isServer = config.networking.hostName == h.host;
    address =
      if isServer
      then "127.0.0.1"
      else "${h.host}.${site.tailnet_domain}";
    # v4.0.0-beta.3 can't read a public ghcr package anonymously, which is all
    # luna does: it asks the token endpoint for pull,push (ghcr denies the whole
    # request), and without a GitHub token it doesn't know it's on ghcr, lists
    # packs by tag, finds none (ghcr content is untagged) and marks every pack
    # evicted. Not filed upstream yet; drop the patch once the input has a fix.
    hestia = inputs.hestia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./hestia-anonymous-pull.patch];
    });
  in {
    options.myNixOS.services.hestia-cache.enable =
      lib.mkEnableOption "myNixOS.services.hestia-cache"
      // {default = true;};

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        # priority 30 asks it before cache.nixos.org (40). It holds no
        # upstream-signed paths (CI's upstream-cache-filter), so those miss
        # here in one cheap lookup.
        nix.settings.substituters =
          lib.mapAttrsToList
          (_: port: "http://${address}:${toString port}?trusted=true&priority=30")
          h.ports;
      }

      (lib.mkIf isServer {
        port-selector.set-ports =
          lib.mapAttrs' (system: port: lib.nameValuePair (toString port) "hestia-${system}") h.ports;

        systemd.services =
          lib.mapAttrs' (system: port:
            lib.nameValuePair "hestia-${system}" {
              description = "hestia substituter for CI's ${system} builds";
              wantedBy = ["multi-user.target"];
              wants = ["network-online.target"];
              after = ["network-online.target"];
              # Public package: anonymous pulls, read-only.
              environment.HESTIA_OCI = h.oci;
              serviceConfig = {
                ExecStart = lib.escapeShellArgs ([
                    "${hestia}/bin/hestia"
                    "serve"
                    "--read-only"
                    "--listen"
                    "[::]:${toString port}"
                    "--socket"
                    "/run/hestia-${system}/hook.sock"
                    "--system"
                    system
                    "--branch"
                    (builtins.head h.branches)
                  ]
                  ++ lib.concatMap (b: ["--serve-branch" b]) (builtins.tail h.branches)
                  # hestia serve reads the published heads at startup and then
                  # only after a failed fetch, because a CI job's daemon lives
                  # for one job. Exiting when idle and coming straight back
                  # picks up what CI pushed since, and never mid-deploy, which
                  # keeps it busy. Drop it if serve learns to relist on a timer.
                  ++ ["--idle-exit" "300"]);
                Restart = "always";
                RestartSec = 1;
                DynamicUser = true;
                RuntimeDirectory = "hestia-${system}";
              };
            })
          h.ports;
      })
    ]);
  };
}
