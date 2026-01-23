{
  pkgs,
  lib,
  config,
  ...
}: let
  secrets = import ../../secrets.nix;
  tdarr_source = pkgs.npinsSources."haveagitgat/tdarr";
  tdarr_api_key = "tapi_nixos_autoconfig_12345";
  pythonWithPackages = pkgs.python3.withPackages (ps: with ps; [requests]);
  tdarr_configure_script = pkgs.writeScriptBin "tdarr-configure" ''
    #!${pythonWithPackages}/bin/python3
    """
    Tdarr Auto-Configuration Script
    Configures Tdarr libraries via API in an idempotent manner
    """

    import os
    import sys
    import time
    import json
    import logging
    import requests
    from typing import Optional, Dict, List

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='[%(asctime)s] %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    logger = logging.getLogger(__name__)

    # Configuration
    TDARR_URL = os.getenv("TDARR_URL", "http://localhost:8265")
    API_KEY = os.getenv("TDARR_API_KEY", "")
    MAX_RETRIES = 30
    RETRY_DELAY = 10

    # API Endpoints
    API_BASE = f"{TDARR_URL}/api/v2"
    STATUS_URL = f"{API_BASE}/status"
    LIBRARIES_URL = f"{API_BASE}/get-libraries"
    CREATE_LIBRARY_URL = f"{API_BASE}/library-settings"
    SCAN_LIBRARY_URL = f"{API_BASE}/scan-library"


    def wait_for_tdarr() -> bool:
        """Wait for Tdarr to be ready."""
        logger.info("Waiting for Tdarr to be ready...")

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                response = requests.get(STATUS_URL, timeout=5)
                if response.status_code == 200:
                    logger.info("✅ Tdarr is ready!")
                    return True
            except requests.exceptions.RequestException:
                pass

            logger.info(f"Tdarr not ready yet, waiting... ({attempt}/{MAX_RETRIES})")
            time.sleep(RETRY_DELAY)

        logger.error("❌ Tdarr failed to start within timeout")
        return False


    def get_libraries() -> Dict:
        """Get all existing libraries."""
        try:
            headers = {"x-api-key": API_KEY} if API_KEY else {}
            response = requests.get(LIBRARIES_URL, headers=headers, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch libraries: {e}")
            return {}


    def library_exists(name: str) -> bool:
        """Check if a library with the given name exists."""
        libraries = get_libraries()

        # Check if any library has this name
        for lib_id, lib_data in libraries.items():
            if lib_data.get("name") == name:
                logger.info(f"📚 Library '{name}' already exists (ID: {lib_id})")
                return True

        return False


    def create_library(name: str, source_path: str, cache_path: str) -> bool:
        """Create a library if it doesn't exist."""
        if library_exists(name):
            return True

        logger.info(f"📚 Creating library: {name}")

        # Library configuration payload
        payload = {
            "name": name,
            "source": source_path,
            "folderToFolderConversion": False,
            "folder_watch": True,
            "priority": 0,
            "scanButtons": {
                "findNew": True,
                "findDeleted": True
            },
            "transcode_cache": cache_path,
            "output_folder": "",
            "pluginStack": []
        }

        try:
            headers = {
                "Content-Type": "application/json",
                "x-api-key": API_KEY
            } if API_KEY else {"Content-Type": "application/json"}

            response = requests.post(
                CREATE_LIBRARY_URL,
                json=payload,
                headers=headers,
                timeout=10
            )

            if response.status_code in [200, 201]:
                logger.info(f"✅ Library '{name}' created successfully")
                return True
            else:
                logger.warning(f"⚠️  Library creation returned status {response.status_code}")
                logger.warning(f"Response: {response.text}")
                return False

        except requests.exceptions.RequestException as e:
            logger.error(f"❌ Failed to create library '{name}': {e}")
            return False


    def main():
        """Main configuration routine."""
        logger.info("🎬 Starting Tdarr auto-configuration (idempotent)...")

        if not API_KEY:
            logger.error("❌ TDARR_API_KEY environment variable not set")
            return 1

        # Wait for Tdarr to be ready
        if not wait_for_tdarr():
            logger.error("⚠️  Tdarr not ready, will retry on next service start")
            return 1

        # Configure libraries
        logger.info("📚 Configuring libraries...")

        libraries_to_create = [
            ("Movies", "/media/movies", "/temp/movies"),
            ("TV Shows", "/media/shows", "/temp/shows"),
        ]

        success_count = 0
        for name, source, cache in libraries_to_create:
            if create_library(name, source, cache):
                success_count += 1
            time.sleep(2)  # Brief delay between API calls

        logger.info(f"✅ Configuration complete! ({success_count}/{len(libraries_to_create)} libraries configured)")
        logger.info(f"📍 Access Tdarr at: {TDARR_URL}")
        logger.info(f"🔑 API Key: {API_KEY}")
        logger.info("")
        logger.info("ℹ️  Note: Plugin configuration must be done via Web UI")
        logger.info("   This service will check on each boot and only create missing libraries")

        return 0


    if __name__ == "__main__":
        sys.exit(main())
  '';
in {
  options = {};
  config = {
    myNixOS.services.caddy.serviceMap = {
      jellyfin = {
        port = 8096;
      };
      jellyseerr = {
        port = 5055;
      };
      sonarr = {
        port = 8989;
      };
      radarr = {
        port = 7878;
      };
      prowlarr = {
        port = 9696;
      };
      bazarr = {
        port = 6767;
      };
      tdarr = {
        port = 8265;
      };
    };
    environment.systemPackages = with pkgs; [
      tremc
      tdarr_configure_script
    ];
    services.flaresolverr.enable = true;
    services.radarr.settings.auth.required = "DisabledForLocalAddresses";
    services.sonarr.settings.auth.required = "DisabledForLocalAddresses";
    services.prowlarr.settings.auth.required = "DisabledForLocalAddresses";
    nixarr = {
      enable = true;
      jellyfin = {
        enable = true;
        libraries = [
          {
            name = "tvshows";
            type = "tvshows";
            paths = ["/storage/downloads/tvshows" "${config.nixarr.mediaDir}/library/shows"];
            enable = true;
          }
          {
            name = "movies";
            type = "movies";
            paths = ["/storage/downloads/movies" "${config.nixarr.mediaDir}/library/movies"];
            enable = true;
          }
        ];
        users = builtins.map ({
          name,
          value,
        }: {
          name = name;
          passwordFile = pkgs.writeText "password" value.password;
          isAdministrator = value.admin;
        }) (lib.attrsets.attrsToList secrets.jellyfin_users);
      };
      jellyseerr.enable = true;
      bazarr.enable = true;
      sonarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };
      radarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };
      prowlarr = {
        enable = true;
        settings-sync = {
          enable-nixarr-apps = true;
        };
      };

      transmission = {
        enable = true;
      };
      mediaDir = "/storage/media";
      stateDir = "/storage/media/.state/nixarr";
    };

    # Tdarr - Media transcoding automation
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.tdarr = {
      hostname = "tdarr";
      imageFile = tdarr_source;
      image = "${tdarr_source.image_name}:${tdarr_source.image_tag}";
      ports = [
        "8265:8265" # Web UI
        "8266:8266" # Server port
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Copenhagen";
        serverIP = "0.0.0.0";
        serverPort = "8266";
        webUIPort = "8265";
        internalNode = "true";
        inContainer = "true";
        nodeName = "MainNode";
        # Pre-seed API key for automated configuration
        seededApiKey = tdarr_api_key;
        # Pre-configure workers for automatic transcoding
        transcodegpuWorkers = "2"; # Adjust based on your GPU
        transcodecpuWorkers = "4"; # Adjust based on your CPU cores
        healthcheckgpuWorkers = "1";
        healthcheckcpuWorkers = "2";
      };
      volumes = [
        "${config.nixarr.stateDir}/tdarr/server:/app/server"
        "${config.nixarr.stateDir}/tdarr/configs:/app/configs"
        "${config.nixarr.stateDir}/tdarr/logs:/app/logs"
        # Media library paths from nixarr config
        "${config.nixarr.mediaDir}/library/movies:/media/movies"
        "${config.nixarr.mediaDir}/library/shows:/media/shows"
        "/storage/downloads/movies:/downloads/movies"
        "/storage/downloads/tvshows:/downloads/tvshows"
        # Temp directory for transcoding
        "/tmp/tdarr:/temp"
      ];
      extraOptions = [
        "--network=host"
        #"--gpus=all"
      ];
    };

    # Systemd service to auto-configure Tdarr via API
    # This service is idempotent - it checks if libraries exist before creating them
    systemd.services.tdarr-configure = {
      description = "Tdarr Auto-Configuration Service";
      after = ["docker-tdarr.service"];
      wants = ["docker-tdarr.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        TDARR_URL = "http://localhost:8265";
        TDARR_API_KEY = tdarr_api_key;
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${tdarr_configure_script}/bin/tdarr-configure";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
  };
}
