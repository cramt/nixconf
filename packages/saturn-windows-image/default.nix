# Build a debloated, app-provisioned Windows 11 image in a headless qemu VM and
# flash it onto a physical partition. Body lives in
# ../../scripts/saturn-windows-image.sh — see its header comment and --help.
#
# Extracted from modules/flake/packages.nix so a NixOS module can depend on it
# too: that file also pulls attrs out of nixosConfigurations.saturn.pkgs, so a
# module reaching for inputs.self.packages would risk infinite recursion.
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
