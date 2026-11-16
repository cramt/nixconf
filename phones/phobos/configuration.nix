# Alex's phone, managed by Nixup (modules/flake/phones.nix). The fleet bits
# (tailscale on headscale, ssh) come from nixupModules; this file is only what's
# specific to the phone. Anything left unset stays as set by hand on the phone.
#
# Once it's rooted, `nix run --inputs-from . nixup#nixup-config -- create` writes
# a config from what it has now (apps, settings, debloat list); merge the parts
# worth keeping into here. Every option, with comments:
# https://github.com/by-architect/Nixup/blob/main/templates/default/configuration.nix
{ pkgs, ... }:
{
  time.timeZone = "Europe/Copenhagen";

  # Apps by repo. F-Droid's names (pkgs.fdroid.<name>) come from the index the
  # phone downloads, so they only evaluate under nixup-rebuild, not plain
  # `nix eval`. Play Store apps are package-name strings and need
  # android.playstore.tokenFile (nix run --inputs-from . nixup#nixup-play-login).
  # android.packages.fdroid = with pkgs.fdroid; [ ];
  # android.packages.playstore = [ ];

  environment.systemPackages = with pkgs; [
    git
    htop
  ];
}
