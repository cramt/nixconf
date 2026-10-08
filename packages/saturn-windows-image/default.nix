# `nix run .#saturn-windows-image -- --build-only` (then `-- --deploy-only
# /dev/…-part1`). Builds a debloated Windows 11 image in a headless raw-qemu
# VM (NVMe disk so it boots on saturn unchanged, no sysprep) and flashes it
# onto a partition. Ships Discord/1Password/Zen via winget at first logon;
# the AMD driver deliberately does NOT come from here (the build VM has no
# GPU) and arrives via Windows Update on first bare-metal boot.
#
# Uses any ISO it finds (~/Downloads included) before falling back to
# uupdump. Verified on 25H2 (26200): ConX is bypassed by forcing
# setup.exe /legacy, and the answer file's locale + edition are derived
# from install.wim rather than assumed — hardcoding en-US against
# "English International" (en-GB-only) media is what previously made
# Setup silently fall back to the interactive installer.
#
# Body lives in ../../scripts/saturn-windows-image.sh; capture/deploy
# self-sudo. See its --help.
{
  lib,
  writeShellApplication,
  qemu,
  swtpm,
  ntfs3g,
  gptfdisk,
  util-linux,
  wimlib,
  p7zip,
  cdrkit,
  hivex,
  git,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  socat,
  imagemagick,
  aria2,
  cabextract,
  chntpw,
  curl,
  jq,
}:
writeShellApplication {
  name = "saturn-windows-image";
  runtimeInputs = [
    qemu swtpm ntfs3g gptfdisk util-linux wimlib p7zip cdrkit hivex
    git coreutils findutils gnugrep gnused gawk socat imagemagick
    aria2 cabextract chntpw curl jq
  ];
  # Strip the two `#!nix-shell` shebang lines — writeShellApplication adds its
  # own. The script stays directly runnable via nix-shell for quick iteration.
  text = let
    raw = builtins.readFile ../../scripts/saturn-windows-image.sh;
  in lib.concatStringsSep "\n" (lib.drop 2 (lib.splitString "\n" raw));
}
