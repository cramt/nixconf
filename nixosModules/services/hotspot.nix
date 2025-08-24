{...}: {
  networking.networkmanager.ensureProfiles.profiles = {
    hotspot = {
      connection = {
        id = "hotspot";
        interface-name = "wlan0";
        type = "wifi";
      };
      ipv4 = {
        method = "shared";
      };
      ipv6 = {
        addr-gen-mode = "default";
        method = "auto";
      };
      proxy = {};
      wifi = {
        band = "bg";
        mode = "ap";
        ssid = "MyHotspot";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "MyPassword";
      };
    };
  };
}
