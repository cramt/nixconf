# 1Password secrets, on every host: `myNixOS.secrets.<name>` declares one and
# op-secrets.service renders it to `myNixOS.secrets.<name>.path` with the
# official `op` CLI (op-secrets.sh). Each host carries the service-account token
# at myLib/secrets.nix's tokenFile (the flash-* images bake it in).
#
# Every NixOS module declares the secrets it reads itself, behind its own
# enable, so a host only renders what it runs: an unused secret is just
# exposure. This file is the plumbing, plus the secrets home-manager reads,
# since an hm module can't declare NixOS secrets.
#
# This replaced opnix, whose Go SDK runs 1Password's core as interpreted WASM
# on anything but x86_64/aarch64: venus (armv7l) took ~20 min per sign-in and
# the server dropped the session before it finished. `op` is a native static
# binary everywhere, ~1.5 s per read.
{...}: {
  flake.nixosModules."security.secrets" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    consts = import ../../myLib/secrets.nix;
    secrets = config.myNixOS.secrets;

    anyHmUser = pred: lib.any pred (lib.attrValues config.home-manager.users);
    # Hosts like mercury import only a subset of the hm features, and eros none
    # of them, so the option can be absent, which can only mean off.
    hmEnabled = path: u: lib.attrByPath (["myHomeManager"] ++ path ++ ["enable"]) false u;

    manifest = pkgs.writeText "op-secrets.jsonl" (lib.concatMapStrings (s:
      builtins.toJSON {inherit (s) name reference path owner group mode services;} + "\n")
    (lib.attrValues secrets));

    render = pkgs.writeShellApplication {
      name = "op-secrets";
      runtimeInputs = with pkgs; [_1password-cli coreutils diffutils jq systemd];
      text = builtins.readFile ./op-secrets.sh;
    };

    consumers = lib.unique (lib.concatMap (s: s.services) (lib.attrValues secrets));

    # User units can't be ordered after op-secrets: a different manager. And
    # waiting for the files inside the unit deadlocks a switch, because
    # switch-to-configuration blocks on every user start job *before* it starts
    # any system unit, so a secret new in that generation never gets rendered
    # (saturn's opnix -> op-secrets deploy hung that way until deploy-rs gave
    # up). So gate instead: a failed Condition ends the start job at once
    # without counting as a failure, and a path unit starts the service when
    # the files land, which also covers boot.
    userConsumers = lib.zipAttrs (lib.concatMap (s: map (u: {${u} = s.path;}) s.userServices)
      (lib.attrValues secrets));
  in {
    options.myNixOS.secrets = lib.mkOption {
      default = {};
      description = "1Password secrets rendered to disk by op-secrets.service.";
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          name = lib.mkOption {
            # It's the file name under the output dir.
            type = lib.types.strMatching "[A-Za-z0-9_-]+";
            default = name;
            readOnly = true;
            internal = true;
          };
          reference = lib.mkOption {
            type = lib.types.strMatching "op://.+";
            example = "op://Homelab/Database/password";
            description = "Secret reference to a field or a file attachment; `op read` takes either.";
          };
          path = lib.mkOption {
            type = lib.types.str;
            default = "${consts.dir}/${name}";
            readOnly = true;
            description = "Where the secret is rendered.";
          };
          owner = lib.mkOption {
            type = lib.types.str;
            default = "root";
          };
          group = lib.mkOption {
            type = lib.types.str;
            default = "root";
          };
          mode = lib.mkOption {
            type = lib.types.strMatching "0?[0-7]{3}";
            default = "0600";
          };
          services = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              System units (without `.service`) that read this secret: they
              start after op-secrets and are restarted when its value changes.
              User units go in `userServices`.
            '';
          };
          userServices = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              NixOS user units (`systemd.user.services`, without `.service`)
              that read this secret, or that can't run without one that does.
              They're skipped while it's missing and started once op-secrets
              writes it. Not restarted when its value changes.
            '';
          };
        };
      }));
    };

    config = {
      users.groups.${consts.group} = {};
      users.users =
        builtins.mapAttrs (name: _: {
          extraGroups = [consts.group];
        })
        config.myNixOS.home-users;

      environment.systemPackages = [pkgs._1password-cli];

      systemd.tmpfiles.rules = [
        # Group-listable so user managers can inotify-watch it for the
        # userServices path units; the files keep their own modes.
        "d ${consts.dir} 0751 root ${consts.group} -"
        # Group-readable so cramt can run `op` with it (infra.nix, the dm-me skill).
        "z ${consts.tokenFile} 0640 root ${consts.group} -"
        # opnix's old render dir, unused since op-secrets. Drop this rule once
        # every host has deployed it.
        "R /var/lib/opnix - - - - -"
      ];

      systemd.services =
        {
          op-secrets = {
            description = "Render 1Password secrets";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target" "nss-lookup.target"];
            wants = ["network-online.target" "nss-lookup.target"];
            # Retry quickly at first (boot races the network), backing off to
            # every 15 min, forever: a host that came up offline picks its
            # secrets up whenever the network does.
            unitConfig.StartLimitIntervalSec = 0;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${lib.getExe render} ${manifest} ${consts.tokenFile} ${consts.dir}";
              Restart = "on-failure";
              RestartSec = "10s";
              RestartSteps = 8;
              RestartMaxDelaySec = "15min";
              TimeoutStartSec = "5min";
              # op keeps its config dir under $HOME.
              RuntimeDirectory = "op-secrets";
              Environment = "HOME=%t/op-secrets";
            };
          };
        }
        // lib.genAttrs consumers (_: {
          after = ["op-secrets.service"];
          wants = ["op-secrets.service"];
        });

      systemd.user.services =
        lib.mapAttrs (_: paths: {unitConfig.ConditionFileNotEmpty = paths;}) userConsumers;

      systemd.user.paths = lib.mapAttrs' (unit: paths: let
        svc = config.systemd.user.services.${unit};
      in
        lib.nameValuePair "${unit}-secrets" {
          description = "Start ${unit} once its 1Password secrets are rendered";
          inherit (svc) wantedBy partOf;
          # Keep e.g. ConditionUser=cramt, so other users' managers don't watch.
          unitConfig = lib.filterAttrs (n: _: n == "ConditionUser") svc.unitConfig;
          pathConfig = {
            PathChanged = paths;
            Unit = "${unit}.service";
          };
        })
      userConsumers;

      # Defining systemd.user.services.<typo> would quietly create a stub unit.
      assertions = lib.mapAttrsToList (unit: _: {
        assertion = config.systemd.user.services.${unit}.serviceConfig ? ExecStart;
        message = "myNixOS.secrets: userServices names `${unit}`, which isn't a user service with an ExecStart.";
      }) userConsumers;

      myNixOS.secrets =
        lib.optionalAttrs (anyHmUser (hmEnabled ["bundles" "general"])) {
          # Included by the user nix.conf (modules/hm-bundles/general.nix)
          # for authenticated github.com tarball fetches. Flake inputs are
          # fetched by the evaluating *client*, not the daemon, so the file
          # has to be readable by the user running nix -- as 0600 root:root
          # the `!include` was a silent no-op and every fetch took the
          # unauthenticated 60/hr rate limit.
          nixAccessTokensConf = {
            reference = "op://Homelab/GitHub/nixAccessTokensConf";
            mode = "0640";
            group = consts.group;
          };
        }
        // lib.optionalAttrs (lib.any (p: anyHmUser (hmEnabled [p])) ["claude-code" "delta"]) {
          cliProxyApiKey = (import ../../myLib/claude-pool.nix).apiKeySecret;
        };
    };
  };
}
