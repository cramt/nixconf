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
    # evicted. hestia-reload-interval adds `--reload-interval`: serve reads the
    # published heads once at startup (a CI job's daemon dies with the job),
    # so a shared one never saw a later push. Neither is filed upstream yet;
    # drop each patch once the input carries an equivalent.
    hestia = inputs.hestia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./hestia-anonymous-pull.patch ./hestia-reload-interval.patch];
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
                  # A CI push is visible within a minute; a relist is a few
                  # anonymous registry requests.
                  ++ ["--reload-interval" "60"]);
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
