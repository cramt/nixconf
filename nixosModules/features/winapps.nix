{...}: let
  home = "/winapps_shared";
in {
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers.WinApps = {
    hostname = "WinApps";
    image = "ghcr.io/dockur/windows:latest";
    environment = {
      VERSION = "11";
      RAM_SIZE = "4G";
      CPU_CORES = "4";
      DISK_SIZE = "64G";
      USERNAME = "MyWindowsUser";
      PASSWORD = "MyWindowsPassword";
      HOME = home;
    };
    ports = [
      "8006:8006"
      "3389:3389/tcp"
      "3389:3389/udp"
    ];
    capabilities.NET_ADMIN = true;
    volumes = [
      "/winapps_storage:/storage"
      "${home}:/shared"
      "/winapps_oem:/oem"
    ];
    devices = [
      "/dev/kvm"
      "/dev/net/tun"
    ];
    extraOptions = [
      "--stop-timeout 120"
    ];
    autoStart = true;
  };
}
