# TP-Link Archer C5 v2 — BCM47081, bcm53xx target.
# Not a NixOS host: nix-openwrt-imagebuilder produces a flashable OpenWrt
# sysupgrade image. Pinned to 19.07.10 because bcm53xx dropped all TP-Link
# devices in 22.03; 19.07.10 is the last release that ships the C5 v2 profile.
{
  pkgs,
  inputs,
  ...
}: let
  # OpenWrt 19.07's ImageBuilder toolchain still pulls Python 2.7. Unstable
  # nixpkgs has now *removed* python2 entirely (not just marked it insecure), so
  # pin this per-build nixpkgs instance to stable (26.05), which still ships
  # python-2.7.18.12. The insecure whitelist is still required there.
  insecurePkgs = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.permittedInsecurePackages = ["python-2.7.18.12"];
  };
in
  inputs.openwrt-imagebuilder.lib.build {
    pkgs = insecurePkgs;
    release = "19.07.10";
    target = "bcm53xx";
    variant = "generic";
    profile = "tplink-archer-c5-v2";

    packages = [
      "luci-ssl"
      "htop"
      "tcpdump-mini"
      "nano"
    ];

    files = insecurePkgs.runCommand "titan-image-files" {} ''
      mkdir -p $out/etc/uci-defaults
      cat > $out/etc/uci-defaults/99-titan <<'EOF'
      uci -q batch <<EOI
      set system.@system[0].hostname='titan'
      commit system
      EOI
      EOF
    '';
  }
