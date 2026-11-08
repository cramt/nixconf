# The wifi networks fleet machines join: eros through myNixOS.wifi, and the
# installer USB through the PSKs flash-installer bakes onto the stick. Shaped
# like myNixOS.wifi.networks, so eros takes it as is.
{
  home = {
    ssid = "The Gayze";
    pskRef = "op://Homelab/li32dfrut7k2gsqwvp4srqitc4/wireless_password";
  };
}
