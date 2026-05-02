{ ... }: {
  flake.nixosModules."services.garage" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.garage;
    api_port = config.port-selector.ports.garage_s3;
    web_port = config.port-selector.ports.garage_web;
    rpc_port = config.port-selector.ports.garage_rpc;
    admin_port = config.port-selector.ports.garage_admin;
    garageBin = lib.getExe config.services.garage.package;

    # Script that idempotently converges garage state to match the declarative config
    setupScript = pkgs.writeShellScript "garage-setup" ''
      set -euo pipefail
      set -a
      [ -f ${lib.escapeShellArg config.services.onepassword-secrets.secretPaths.garageEnv} ] \
        && . ${lib.escapeShellArg config.services.onepassword-secrets.secretPaths.garageEnv}
      set +a

      garage="${garageBin}"

      # Wait for garage to be reachable
      for i in $(seq 1 30); do
        if $garage status >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      # Get the node ID
      node_id=$($garage status 2>/dev/null | ${pkgs.gawk}/bin/awk '/^[0-9a-f]/ {print $1; exit}')
      if [ -z "$node_id" ]; then
        echo "ERROR: could not determine node ID"
        exit 1
      fi

      # Check if layout already has this node assigned
      layout_has_node=$($garage layout show 2>/dev/null | grep -c "$node_id" || true)
      if [ "$layout_has_node" -eq 0 ]; then
        echo "Assigning node $node_id to layout..."
        $garage layout assign -z dc1 -c ${lib.escapeShellArg cfg.capacity} "$node_id"
        $garage layout apply --version 1 2>/dev/null \
          || $garage layout apply --version $($garage layout show | ${pkgs.gawk}/bin/awk '/Current cluster layout version:/ {print $NF + 1}')
      fi

      # Converge buckets
      existing_buckets=$($garage bucket list 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR>1 {print $2}' || true)
      ${lib.concatMapStringsSep "\n" (bucket: ''
        if ! echo "$existing_buckets" | grep -qx "${bucket}"; then
          echo "Creating bucket: ${bucket}"
          $garage bucket create "${bucket}"
        fi
      '') cfg.buckets}

      # Converge keys
      existing_keys=$($garage key list 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR>1 {print $2}' || true)
      ${lib.concatMapStringsSep "\n" (key: ''
        if ! echo "$existing_keys" | grep -qx "${key.name}"; then
          echo "Creating key: ${key.name}"
          $garage key create "${key.name}"
        fi
        ${lib.concatMapStringsSep "\n" (bucket: ''
          echo "Allowing key ${key.name} on bucket ${bucket}"
          $garage bucket allow --read --write --owner "${bucket}" --key "${key.name}" 2>/dev/null || true
        '') key.buckets}
      '') cfg.keys}

      echo "Garage setup complete"
    '';
  in {
    options.myNixOS.services.garage = {
      enable = lib.mkEnableOption "myNixOS.services.garage";
      capacity = lib.mkOption {
        type = lib.types.str;
        default = "1T";
        description = "Storage capacity to assign to this node";
      };
      buckets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Buckets to create declaratively";
      };
      keys = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "API key name";
            };
            buckets = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Buckets this key has read/write/owner access to";
            };
          };
        });
        default = [];
        description = "API keys to create declaratively";
      };
    };
    config = lib.mkIf cfg.enable {
      myNixOS.services.caddy.serviceMap = {
        bucketapi = {
          port = api_port;
        };
        bucket = {
          port = web_port;
        };
      };
      port-selector.auto-assign = ["garage_s3" "garage_web" "garage_rpc" "garage_admin"];
      services.garage = {
        enable = true;
        package = pkgs.garage;
        environmentFile = config.services.onepassword-secrets.secretPaths.garageEnv;
        settings = {
          replication_mode = "1";
          metadata_dir = "/storage/garage/meta";
          data_dir = "/storage/garage/data";
          rpc_bind_addr = "[::]:${builtins.toString rpc_port}";
          s3_api = {
            s3_region = "garage";
            api_bind_addr = "[::]:${builtins.toString api_port}";
            root_domain = ".s3.garage.localhost";
          };
          s3_web = {
            bind_addr = "[::]:${builtins.toString web_port}";
            root_domain = ".web.garage.localhost";
          };
          admin = {
            api_bind_addr = "[::]:${builtins.toString admin_port}";
          };
        };
      };
      systemd.services.garage-setup = {
        description = "Declarative Garage layout, bucket, and key setup";
        after = ["garage.service"];
        requires = ["garage.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = setupScript;
          ReadWritePaths = [
            config.services.garage.settings.metadata_dir
            config.services.garage.settings.data_dir
          ];
        };
      };
    };
  };
}
